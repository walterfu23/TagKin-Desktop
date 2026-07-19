# 101_setup.ps1 — first-clone setup: fetch Dart deps + generate contract models.
# Run once after cloning, or after a Flutter/toolchain change.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) '_env.ps1')

Write-Host '==> flutter --version'
flutter --version
Write-Host '==> flutter pub get'
flutter pub get
Write-Host '==> contract codegen'
& (Join-Path (Split-Path -Parent $PSCommandPath) '102_codegen.ps1')
Write-Host '==> setup complete'
