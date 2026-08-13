# 110_test_d4.ps1 — D4 Client Pre-pass regression: EXIF when/where, dHash
# confirm, ffmpeg scene detect + adaptive frame sampling (hard cap), stub
# face embed, POST /items/{id}/pre-pass-result payload has no media bytes,
# R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.ps1 for desktop subsystem regression Windows entry points.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

Write-Host '==> flutter analyze'
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> flutter test (unit/widget + D4 prepass)'
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Invoke-TagKinR8SecretScan

Write-Host '==> integration smoke (prepass on Windows)'
flutter test integration_test/prepass_test.dart -d windows
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> D4 regression complete'
