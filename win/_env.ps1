# Shared Windows helper for TagKin-Desktop/win/*.ps1 — dot-source this; do not run directly.
# Sets the desktop repo root + ensures the Flutter SDK is on PATH.

$ErrorActionPreference = 'Stop'

$script:TagKinDesktopWinDir = Split-Path -Parent $PSCommandPath
$global:TagKinDesktopRoot = (Resolve-Path (Join-Path $script:TagKinDesktopWinDir '..')).Path
Set-Location $global:TagKinDesktopRoot

# Common Flutter install locations. Extend as needed.
$flutterCandidates = @(
  (Join-Path $global:TagKinDesktopRoot '.fvm\flutter_sdk\bin'),
  'C:\flutter\bin',
  (Join-Path $env:USERPROFILE 'flutter\bin'),
  (Join-Path $env:USERPROFILE 'development\flutter\bin')
)
foreach ($c in $flutterCandidates) {
  if (Test-Path $c) { $env:PATH = "$c;$env:PATH" }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Error @"
flutter not found on PATH.
Install the Flutter stable SDK (https://docs.flutter.dev/get-started/install/windows)
or add its bin\ to PATH, then re-run.
"@
}

# Ensure desktop is enabled (idempotent, cheap).
flutter config --enable-windows-desktop | Out-Null
