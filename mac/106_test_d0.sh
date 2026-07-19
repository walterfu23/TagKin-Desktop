#!/usr/bin/env bash
# 106_test_d0.sh — D0 Foundation regression: contract codegen determinism, terminology
# parity (R2), analyze clean, and the unit + integration smoke suite.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> codegen (must produce no uncommitted drift)"
"${MAC_DIR}/102_codegen.sh"
if [[ -d "${TAGKIN_DESKTOP_ROOT}/.git" ]]; then
  # Intent-to-add so untracked new files also show up in `git diff` (tracked-only
  # `git diff` silently ignores never-committed output and would miss first-clone drift).
  git -C "${TAGKIN_DESKTOP_ROOT}" add -N -- lib/contract 2>/dev/null || true
  if ! git -C "${TAGKIN_DESKTOP_ROOT}" diff --quiet -- lib/contract 2>/dev/null; then
    echo "error: generated Dart contract models drifted — commit regenerated output." >&2
    git -C "${TAGKIN_DESKTOP_ROOT}" --no-pager diff --stat -- lib/contract || true
    exit 1
  fi
fi

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D0 terminology-parity)"
flutter test

echo "==> integration smoke (foundation boot on macOS)"
flutter test integration_test/app_test.dart -d macos

echo "==> D0 regression complete"
