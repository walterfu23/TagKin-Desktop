# 106_test_d0.ps1 — D0 Foundation regression: contract codegen determinism, terminology
# parity (R2), analyze clean, and the unit + integration smoke suite.
# Naming: NNN_test_dN.ps1 for desktop subsystem regression Windows entry points.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

Write-Host '==> codegen (must produce no uncommitted drift)'
& (Join-Path $winDir '102_codegen.ps1')
if ((Test-Path (Join-Path $global:TagKinDesktopRoot '.git'))) {
  # Intent-to-add so untracked new files also show up in `git diff` (tracked-only
  # `git diff` silently ignores never-committed output and would miss first-clone drift).
  git -C $global:TagKinDesktopRoot add -N -- lib/contract 2>$null
  git -C $global:TagKinDesktopRoot diff --quiet -- lib/contract
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'error: generated Dart contract models drifted — commit regenerated output.'
    git -C $global:TagKinDesktopRoot --no-pager diff --stat -- lib/contract
    exit 1
  }
}

Write-Host '==> flutter analyze'
flutter analyze

Write-Host '==> flutter test (unit/widget + D0 terminology-parity)'
flutter test

Write-Host '==> integration smoke (foundation boot on Windows)'
flutter test integration_test/app_test.dart -d windows

Write-Host '==> D0 regression complete'
