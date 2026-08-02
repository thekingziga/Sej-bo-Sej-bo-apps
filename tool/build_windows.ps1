# Sejbosejbo - Windows build helper
#
# Run this INSIDE the Parallels Windows 11 VM, in PowerShell, as Administrator.
# It installs what Flutter needs, copies the project off the Mac share onto the
# VM's local disk, and builds the Windows app.
#
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   \\Mac\Home\Projects\PROJECT\sejbosejbo-app\tool\build_windows.ps1
#
# Why copy instead of building on the share: Flutter's Windows build uses CMake
# and long nested paths, and building over the \\Mac\ SMB share is both slow and
# prone to failing on path length and file locking. Local disk is the safe path.

$ErrorActionPreference = 'Stop'

$FlutterRoot = 'C:\src\flutter'
$WorkRoot    = 'C:\dev\sejbosejbo-app'
$MacProject  = '\\Mac\Home\Projects\PROJECT\sejbosejbo-app'

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  ok   $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  warn $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------- prerequisites

Step 'Checking prerequisites'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "winget is missing. Install 'App Installer' from the Microsoft Store, then re-run."
}
Ok 'winget'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Step 'Installing Git'
  winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path', 'User')
}
Ok 'git'

# Flutter needs the real Visual Studio C++ toolchain. Build Tools alone is not
# enough for `flutter doctor` to report the Windows toolchain as ready.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasCpp = $false
if (Test-Path $vswhere) {
  $found = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if ($found) { $hasCpp = $true; Ok "Visual Studio C++ toolchain: $found" }
}

if (-not $hasCpp) {
  Warn 'Visual Studio with "Desktop development with C++" is NOT installed.'
  Warn 'This is a ~10 GB download and the one step that genuinely takes a while.'
  $answer = Read-Host 'Install Visual Studio 2022 Community now? (y/N)'
  if ($answer -eq 'y') {
    winget install --id Microsoft.VisualStudio.2022.Community -e --source winget `
      --accept-package-agreements --accept-source-agreements `
      --override '--quiet --wait --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended'
  } else {
    throw 'Cannot build for Windows without the C++ workload. Install it and re-run.'
  }
}

# --------------------------------------------------------------------- flutter

if (-not (Test-Path $FlutterRoot)) {
  Step 'Cloning Flutter (stable)'
  New-Item -ItemType Directory -Force -Path (Split-Path $FlutterRoot) | Out-Null
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git $FlutterRoot
}
$env:Path = "$FlutterRoot\bin;$env:Path"
Ok "flutter at $FlutterRoot"

Step 'flutter doctor'
flutter doctor

# ------------------------------------------------------------------ the project

Step 'Copying the project to local disk'
if (-not (Test-Path $MacProject)) {
  throw "Cannot see $MacProject. In Parallels: Configure > Options > Sharing, " +
        "enable 'Share Mac folders with Windows' (Home folder), then re-run."
}

New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
# /MIR mirrors; skip build output and local tool state, which are huge, Mac
# specific, and would only confuse the Windows build.
robocopy $MacProject $WorkRoot /MIR /NFL /NDL /NJH /NJS /NP `
  /XD build .dart_tool .git ios macos android .idea | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }
Ok "copied to $WorkRoot"

Set-Location $WorkRoot

Step 'Resolving dependencies'
flutter pub get

Step 'Building Windows release'
flutter build windows --release

$exe = Join-Path $WorkRoot 'build\windows\x64\runner\Release\sejbosejbo.exe'
if (Test-Path $exe) {
  Step 'Done'
  Ok $exe
  Write-Host "`nRun it with:`n  & '$exe'`n"
} else {
  throw 'Build reported success but the exe is missing. Check the output above.'
}
