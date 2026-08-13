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

# R8: no long-lived secrets in client source. Used by NNN_test_dN bars and CI.
function Invoke-TagKinR8SecretScan {
  Write-Host '==> R8 secret scan (lib/ must not contain sk_test_/sk_live_/CLERK_SECRET_KEY)'
  $hits = Select-String -Path (Join-Path $global:TagKinDesktopRoot 'lib\**\*.dart') -Pattern 'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY' -ErrorAction SilentlyContinue
  if ($hits) {
    Write-Host 'error: forbidden secret pattern found under lib/'
    $hits | ForEach-Object { Write-Host $_ }
    exit 1
  }
}
