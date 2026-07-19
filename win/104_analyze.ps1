# 104_analyze.ps1 — static analysis bar (flutter analyze). Keep zero analyzer issues.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) '_env.ps1')

Write-Host '==> flutter analyze'
flutter analyze
Write-Host '==> analyze complete'
