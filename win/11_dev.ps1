# 11_dev.ps1 — run the desktop app on Windows (foreground, live console). Band 11-49 = ops.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) '_env.ps1')

Write-Host '==> flutter run -d windows'
flutter run -d windows @args
