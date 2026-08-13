#!/usr/bin/env bash
# 117_test_d12.sh — D12 Per-screen Undo/Redo regression:
# UndoController LIFO; Review correction undo/redo; read-only corrections history;
# R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D12 undo)"
flutter test test/undo/undo_controller_test.dart test/review_controller_test.dart test/knowledge_corrections_ui_test.dart

tagkin_r8_secret_scan

echo "==> integration smoke (knowledge corrections + screen undo on macOS)"
flutter test integration_test/knowledge_corrections_test.dart -d macos

echo "==> D12 regression complete"
