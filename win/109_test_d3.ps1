# 109_test_d3.ps1 — D3 Local Folder Ingest & Batch regression: media
# enumeration + type filtering, content/perceptual hash dedup (incl.
# existing-library check), batch POST /items (refs/hashes only), R10 tenant
# isolation, §5 mandatory assertions.
# Naming: NNN_test_dN.ps1 for desktop subsystem regression Windows entry points.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

Write-Host '==> flutter analyze'
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> flutter test (unit/widget + D3 ingest)'
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Invoke-TagKinR8SecretScan

Write-Host '==> integration smoke (folder ingest on Windows)'
flutter test integration_test/folder_ingest_test.dart -d windows
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> D3 regression complete'
