#!/usr/bin/env bash
# 116_test_d10.sh — D10 Knowledge Corrections & Comments UI regression:
# tag add/edit/remove/undo, captured-at, key-period bounds, comments;
# R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D10 corrections/comments)"
flutter test

echo "==> R8 secret scan (lib/ must not contain sk_test_/sk_live_/CLERK_SECRET_KEY)"
if grep -R -n -E 'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY' lib/ >/dev/null 2>&1; then
  echo "error: forbidden secret pattern found under lib/" >&2
  grep -R -n -E 'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY' lib/ >&2 || true
  exit 1
fi

echo "==> integration smoke (knowledge corrections UI on macOS)"
flutter test integration_test/knowledge_corrections_test.dart -d macos

echo "==> D10 regression complete"
