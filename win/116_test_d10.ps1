# 116_test_d10.ps1 — D10 Knowledge Corrections & Comments UI regression:
# tag add/edit/remove/undo, captured-at, key-period bounds, comments;
# R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.ps1 for desktop subsystem regression Windows entry points.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

Write-Host '==> flutter analyze'
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> flutter test (unit/widget + D10 corrections/comments)'
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> R8 secret scan (lib/ must not contain sk_test_/sk_live_/CLERK_SECRET_KEY)'
$hits = Select-String -Path (Join-Path $global:TagKinDesktopRoot 'lib\**\*.dart') -Pattern 'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY' -ErrorAction SilentlyContinue
if ($hits) {
  Write-Host 'error: forbidden secret pattern found under lib/'
  $hits | ForEach-Object { Write-Host $_ }
  exit 1
}

Write-Host '==> integration smoke (knowledge corrections UI on Windows)'
flutter test integration_test/knowledge_corrections_test.dart -d windows
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> D10 regression complete'
