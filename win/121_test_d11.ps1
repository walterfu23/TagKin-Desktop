# 121_test_d11.ps1 — D11 Packaging, Signing & Update regression:
# X-TagKin-Client header, warn banner, Update required screen, Settings About;
# R8 / §5 mandatory assertions. Signed Sparkle/MSIX install is operator/CI
# once code-signing certs exist — this bar does not notarize.
# Naming: NNN_test_dN.ps1 for desktop subsystem regression Windows entry points.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

Write-Host '==> flutter analyze'
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> flutter test (unit/widget + D11 client version / update UI)'
flutter test test/api_client_test.dart test/client_version_ui_test.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Invoke-TagKinR8SecretScan

Write-Host '==> version stamp (pubspec version is what PackageInfo reports)'
$verLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:' | Select-Object -First 1
if (-not $verLine) { Write-Error 'error: pubspec version missing' }
Write-Host ("ok: {0}" -f $verLine.Line)

Write-Host '==> D11 regression complete'
