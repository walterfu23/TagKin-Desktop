#!/usr/bin/env bash
# 107_test_d1.sh — D1 Auth & Account regression: ApiClient /me, secure store,
# 401→sign-in, no ownerUserId in bodies, R8 secret scan, auth shell widgets.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D1 auth/API/trust-boundary)"
flutter test

echo "==> R8 secret scan (lib/ must not contain sk_test_/sk_live_/CLERK_SECRET_KEY)"
if grep -R -n -E 'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY' lib/ >/dev/null 2>&1; then
  echo "error: forbidden secret pattern found under lib/" >&2
  grep -R -n -E 'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY' lib/ >&2 || true
  exit 1
fi

echo "==> integration smoke (signed-in foundation boot on macOS)"
flutter test integration_test/app_test.dart -d macos

echo "==> D1 regression complete"
