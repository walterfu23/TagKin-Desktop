# 11_dev.ps1 — run the desktop app on Windows (foreground, live console). Band 11-49 = ops.
# Loads CLERK_PUBLISHABLE_KEY / TAGKIN_API_URL from .env and passes them via
# --dart-define (mirrors mac/11_dev.sh).
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) '_env.ps1')

$envFile = Join-Path $global:TagKinDesktopRoot '.env'
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }
    $eq = $line.IndexOf('=')
    if ($eq -le 0) { return }
    $key = $line.Substring(0, $eq).Trim()
    $val = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
    if ($key -eq 'CLERK_PUBLISHABLE_KEY' -or $key -eq 'TAGKIN_API_URL') {
      Set-Item -Path "Env:$key" -Value $val
    }
  }
}

if (-not $env:CLERK_PUBLISHABLE_KEY) {
  Write-Warning 'CLERK_PUBLISHABLE_KEY unset — run ./103_clerk-env.ps1 or create .env'
}

$defines = @()
if ($env:CLERK_PUBLISHABLE_KEY) {
  $defines += "--dart-define=CLERK_PUBLISHABLE_KEY=$($env:CLERK_PUBLISHABLE_KEY)"
}
if ($env:TAGKIN_API_URL) {
  $defines += "--dart-define=TAGKIN_API_URL=$($env:TAGKIN_API_URL)"
}

Write-Host '==> flutter run -d windows'
flutter run -d windows @defines @args
