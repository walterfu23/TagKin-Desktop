# 123_test_d13.ps1 — D13 Item List Export regression: filter body, reorder,
# CSV export, R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.ps1 for desktop subsystem regression Windows entry points.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

Write-Host '==> flutter analyze'
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> flutter test (unit/widget + D13 item list export)'
flutter test test/item_lists test/d13_trust_boundary_test.dart test/local_thumb_cache_test.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Invoke-TagKinR8SecretScan

Write-Host '==> D13 regression complete'
