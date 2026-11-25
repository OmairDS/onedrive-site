# One-time setup: OneDrive "Website" folder -> GitHub Pages
# Run:  powershell -ExecutionPolicy Bypass -File setup.ps1

$Source   = "C:\Users\Omair\OneDrive\Desktop\Website"
$Sites    = "C:\sites"
$RepoName = "onedrive-site"
$Repo     = Join-Path $Sites $RepoName

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "Git is not installed." -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $Source)) { Write-Host "Source folder not found: $Source" -ForegroundColor Red; exit 1 }

$User = Read-Host "Your GitHub username"
if (-not $User) { Write-Host "GitHub username is required." -ForegroundColor Red; exit 1 }

New-Item -ItemType Directory -Force -Path $Sites | Out-Null

if (-not (Test-Path (Join-Path $Repo ".git"))) {
  Set-Location $Sites
  git clone "https://github.com/$User/$RepoName.git"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Clone failed. Create a PUBLIC repo named '$RepoName' (tick 'Add a README') on github.com first, then run this again." -ForegroundColor Red
    exit 1
  }
}

Set-Location $Repo
git config user.name $User
git config user.email "$User@users.noreply.github.com"

$utf8 = New-Object System.Text.UTF8Encoding $false

# --- .nojekyll ---
[System.IO.File]::WriteAllText((Join-Path $Repo ".nojekyll"), "", $utf8)

# --- index.html ---
$index = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Files</title>
<style>
  body{font-family:system-ui,sans-serif;max-width:800px;margin:2rem auto;padding:0 1rem;color:#222}
  input{width:100%;padding:.6rem;margin-bottom:1rem;font-size:1rem}
  details{margin:.25rem 0 .25rem 1rem}
  summary{cursor:pointer;font-weight:600}
  a{display:block;margin:.2rem 0 .2rem 2rem;text-decoration:none;color:#0a58ca}
  .new{background:#e6f4ea;color:#137333;font-size:.7rem;padding:.1rem .4rem;border-radius:8px;margin-inline-start:.4rem}
  .meta{color:#888;font-size:.8rem}
</style>
</head>
<body>
<h1>Files</h1>
<input id="q" placeholder="Search...">
<div id="app">Loading...</div>
<script>
const WEEK = 7*24*3600*1000;
const arr = x => x == null ? [] : [].concat(x);
const esc = s => s.replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const fmt = b => b > 1048576 ? (b/1048576).toFixed(1)+" MB" : Math.max(1, Math.ceil(b/1024))+" KB";
const href = p => "files/" + p.split("/").map(encodeURIComponent).join("/");
let data = [];

function render(items, q) {
  return arr(items).map(i => {
    if (i.isFolder) {
      const inner = render(i.children, q);
      if (q && !inner && !i.name.toLowerCase().includes(q)) return "";
      return `<details ${q ? "open" : ""}><summary dir="auto">&#128193; ${esc(i.name)}</summary>${inner}</details>`;
    }
    if (q && !i.name.toLowerCase().includes(q)) return "";
    const isNew = Date.now() - new Date(i.modified) < WEEK;
    return `<a dir="auto" href="${href(i.path)}">&#128196; ${esc(i.name)}
      <span class="meta">${fmt(i.size)}</span>${isNew ? '<span class="new">new</span>' : ""}</a>`;
  }).join("");
}

function draw() {
  const q = document.getElementById("q").value.trim().toLowerCase();
  document.getElementById("app").innerHTML = render(data, q) || "Nothing found.";
}

fetch("files.json?" + Date.now())
  .then(r => r.json())
  .then(d => { data = arr(d); draw(); })
  .catch(() => { document.getElementById("app").textContent = "Could not load the file list."; });
document.getElementById("q").addEventListener("input", draw);
</script>
</body>
</html>
'@
[System.IO.File]::WriteAllText((Join-Path $Repo "index.html"), $index, $utf8)

# --- sync.ps1 (kept outside the repo) ---
$sync = @'
$Source = "__SOURCE__"
$Repo   = "__REPO__"
$Dest   = Join-Path $Repo "files"

if (-not (Test-Path -LiteralPath $Source)) { exit 1 }

robocopy $Source $Dest /MIR /XF desktop.ini Thumbs.db /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { exit 1 }

function Build($dir, $rel) {
  Get-ChildItem -LiteralPath $dir | Sort-Object @{e={-not $_.PSIsContainer}}, Name | ForEach-Object {
    $p = if ($rel) { "$rel/$($_.Name)" } else { $_.Name }
    if ($_.PSIsContainer) {
      [ordered]@{ name=$_.Name; path=$p; isFolder=$true; children=@(Build $_.FullName $p) }
    } else {
      [ordered]@{ name=$_.Name; path=$p; isFolder=$false; size=$_.Length; modified=$_.LastWriteTimeUtc.ToString("o") }
    }
  }
}
$tree = @(Build $Dest "")
$json = ConvertTo-Json -InputObject $tree -Depth 50
[System.IO.File]::WriteAllText((Join-Path $Repo "files.json"), $json, (New-Object System.Text.UTF8Encoding $false))

Set-Location $Repo
git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) { git commit -q -m "Sync $(Get-Date -Format s)" | Out-Null }
$ahead = git rev-list --count '@{u}..HEAD' 2>$null
if ([int]$ahead -gt 0) { git push -q }
'@
$sync = $sync.Replace("__SOURCE__", $Source).Replace("__REPO__", $Repo)
$syncPath = Join-Path $Sites "sync.ps1"
[System.IO.File]::WriteAllText($syncPath, $sync, $utf8)

# --- hidden launcher so no console window flashes every minute ---
$vbs = 'CreateObject("Wscript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""' + $syncPath + '""", 0, False'
$vbsPath = Join-Path $Sites "run-hidden.vbs"
[System.IO.File]::WriteAllText($vbsPath, $vbs, $utf8)

# --- first sync (a GitHub sign-in window may open: approve it) ---
Write-Host "Running first sync. If a GitHub sign-in window opens, sign in and approve." -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $syncPath

# --- scheduled task: every minute, also on battery ---
$action   = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsPath`""
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName "OneDriveSiteSync" -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Last step: on github.com open the repo > Settings > Pages > Deploy from a branch > main / (root) > Save."
Write-Host "Your site will be at: https://$User.github.io/$RepoName/"
