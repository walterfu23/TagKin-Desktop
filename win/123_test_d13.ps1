# 123_test_d13.ps1 — D13 Item List Export regression: Views dropdown, reorder,
# JSON / FCP7 XML / FCPXML / MP4-with-music export, R10/R1/R5/R8 §5
# mandatory assertions.
# Naming: NNN_test_dN.ps1 for desktop subsystem regression Windows entry points.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

Write-Host '==> flutter analyze'
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> flutter test (unit/widget + D13 item list export)'
flutter test test/item_lists test/d13_trust_boundary_test.dart test/local_thumb_cache_test.dart test/sharpness_test.dart test/prepass/sharpness_score_chip_test.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Invoke-TagKinR8SecretScan

Write-Host '==> D13 vendor-name scan (R8 — client must not name music vendors)'
$vendorHits = @()
$vendorHits += Get-ChildItem -Path 'lib' -Recurse -Filter '*.dart' |
  Select-String -Pattern 'ElevenLabs|Mubert|Loudly|AIVA|Soundraw|ELEVENLABS_API_KEY'
if (Test-Path 'assets') {
  $vendorHits += Get-ChildItem -Path 'assets' -Recurse -File |
    Select-String -Pattern 'ElevenLabs|Mubert|Loudly|AIVA|Soundraw|ELEVENLABS_API_KEY'
}
if ($vendorHits) {
  $vendorHits | ForEach-Object { Write-Host $_.Line }
  throw 'music vendor name or key found under lib/'
}

Write-Host '==> D13 regression complete'
