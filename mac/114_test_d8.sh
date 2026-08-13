#!/usr/bin/env bash
# 114_test_d8.sh — D8 Review UI regression: knowledge display, local media
# resolution, key-period scrub; R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D8 review)"
flutter test

tagkin_r8_secret_scan

echo "==> integration smoke (review UI on macOS)"
flutter test integration_test/review_test.dart -d macos

echo "==> D8 regression complete"
