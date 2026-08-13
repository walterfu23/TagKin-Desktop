# 117_test_d12.ps1 — D12 Per-screen Undo/Redo regression:
# UndoController LIFO; Review correction undo/redo; read-only corrections history;
# R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.ps1 for desktop subsystem regression Windows entry points.
$ErrorActionPreference = 'Stop'
$winDir = Split-Path -Parent $PSCommandPath
. (Join-Path $winDir '_env.ps1')

Write-Host '==> flutter analyze'
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> flutter test (unit/widget + D12 undo)'
flutter test test/undo/undo_controller_test.dart test/review_controller_test.dart test/knowledge_corrections_ui_test.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Invoke-TagKinR8SecretScan

Write-Host '==> integration smoke (knowledge corrections + screen undo on Windows)'
flutter test integration_test/knowledge_corrections_test.dart -d windows
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> D12 regression complete'
