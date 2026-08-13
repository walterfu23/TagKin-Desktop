# 108_test_d2.ps1 — D2 Library & Item Registry regression: ItemsRepository,
# wide library table (thumb/who/what/where/source), client sort/filter/page,
# processingStatus mapping, detail UI, no-bytes create, R10 tenant isolation,
# §5 mandatory assertions.
# Naming: NNN_test_dN.ps1 for desktop subsystem regression Windows entry points.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

Write-Host '==> flutter analyze'
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> flutter test (unit/widget + D2 library)'
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Invoke-TagKinR8SecretScan

Write-Host '==> integration smoke (library list/detail on Windows)'
flutter test integration_test/items_test.dart -d windows
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> D2 regression complete'
