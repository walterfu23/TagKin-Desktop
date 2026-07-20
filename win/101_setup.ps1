# 101_setup.ps1 — first-clone setup: fetch Dart deps + generate contract models
# + embeddable ffmpeg binaries for D4 (shipped next to the exe; end users never
# install ffmpeg).
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) '_env.ps1')

Write-Host '==> flutter --version'
flutter --version

Write-Host '==> flutter pub get'
flutter pub get
Write-Host '==> contract codegen'
& (Join-Path (Split-Path -Parent $PSCommandPath) '102_codegen.ps1')

Write-Host '==> bundled ffmpeg for D4 (app-shipped; not a user install step)'
& (Join-Path (Split-Path -Parent $PSCommandPath) '105_fetch_ffmpeg.ps1')

Write-Host '==> setup complete'
