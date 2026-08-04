# Sejbosejbo - Windows build
#
# Run this on the Windows PC, in PowerShell, from inside the extracted folder:
#
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\tool\build_windows.ps1
#
# It installs Git and Flutter if missing, checks for the Visual Studio C++
# toolchain, and builds. The resulting folder under build\windows\ is
# self-contained - copy it anywhere and run sejbosejbo.exe.

$ErrorActionPreference = 'Stop'

$FlutterRoot = 'C:\src\flutter'
# Baked into the binary. Without it the app silently starts in demo mode on
# bundled sample posts instead of talking to the real site.
$ApiBaseUrl  = 'https://sejbosejbo.fyi'

# Project root = parent of this script's folder, so the script works no matter
# where the zip was extracted.
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  ok   $m"   -ForegroundColor Green }
function Warn($m) { Write-Host "  warn $m"   -ForegroundColor Yellow }

Step "Project root"
Ok $ProjectRoot
if (-not (Test-Path (Join-Path $ProjectRoot 'pubspec.yaml'))) {
  throw "No pubspec.yaml in $ProjectRoot - run this from inside the extracted project folder."
}

# ---------------------------------------------------------------- prerequisites

Step 'Checking prerequisites'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "winget is missing. Install 'App Installer' from the Microsoft Store, then re-run."
}
Ok 'winget'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Step 'Installing Git'
  winget install --id Git.Git -e --source winget `
    --accept-package-agreements --accept-source-agreements --disable-interactivity
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path','User')
}
Ok "git ($((git --version)))"

# Flutter needs the real Visual Studio C++ toolchain; Build Tools alone is not
# enough for `flutter doctor` to report the Windows toolchain as ready.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasCpp = $false
if (Test-Path $vswhere) {
  if (& $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) {
    $hasCpp = $true
  }
}

if (-not $hasCpp) {
  Warn 'Visual Studio with "Desktop development with C++" is NOT installed.'
  Warn 'This is a ~10 GB download and by far the longest step. Everything else takes minutes.'
  if ((Read-Host 'Install Visual Studio 2022 Community now? (y/N)') -ne 'y') {
    throw 'Cannot build for Windows without the C++ workload.'
  }
  winget install --id Microsoft.VisualStudio.2022.Community -e --source winget `
    --accept-package-agreements --accept-source-agreements `
    --override '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended'
}
Ok 'Visual Studio C++ toolchain'

# --------------------------------------------------------------------- flutter

if (-not (Test-Path "$FlutterRoot\bin\flutter.bat")) {
  Step 'Cloning Flutter (stable) - a few minutes'
  New-Item -ItemType Directory -Force -Path (Split-Path $FlutterRoot) | Out-Null
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git $FlutterRoot
}
$env:Path = "$FlutterRoot\bin;$env:Path"
Ok "flutter at $FlutterRoot"

Step 'flutter doctor'
flutter doctor

# ----------------------------------------------------------------------- build

Set-Location $ProjectRoot

Step 'Resolving dependencies'
flutter pub get

Step 'Building Windows release'
flutter build windows --release --dart-define="API_BASE_URL=$ApiBaseUrl"

# x64 on a normal PC, arm64 on Windows-on-ARM. Find whichever was produced
# rather than assuming.
$exe = Get-ChildItem -Path (Join-Path $ProjectRoot 'build\windows') `
        -Filter 'sejbosejbo.exe' -Recurse -ErrorAction SilentlyContinue |
       Where-Object { $_.FullName -like '*\Release\*' } |
       Select-Object -First 1

if (-not $exe) { throw 'Build reported success but no sejbosejbo.exe was found.' }

Step 'Done'
Ok $exe.FullName
Write-Host ''
Write-Host '  The whole Release folder is the app - copy it somewhere and run the exe.'
Write-Host '  Everything beside it (the DLLs and the data folder) is required.'
Write-Host ''
Write-Host "  Run now with:  & '$($exe.FullName)'"
Write-Host ''
