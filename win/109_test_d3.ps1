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

Write-Host '==> R8 secret scan (lib/ must not contain sk_test_/sk_live_/CLERK_SECRET_KEY)'
$hits = Select-String -Path (Join-Path $global:TagKinDesktopRoot 'lib\**\*.dart') -Pattern 'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY' -ErrorAction SilentlyContinue
if ($hits) {
  Write-Host 'error: forbidden secret pattern found under lib/'
  $hits | ForEach-Object { Write-Host $_ }
  exit 1
}

Write-Host '==> integration smoke (folder ingest on Windows)'
flutter test integration_test/folder_ingest_test.dart -d windows
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> D3 regression complete'
