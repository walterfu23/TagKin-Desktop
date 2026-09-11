#!/usr/bin/env bash
# 123_test_d13.sh — D13 Item List Export regression: filter body, reorder,
# CSV export, R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D13 item list export)"
flutter test test/item_lists test/d13_trust_boundary_test.dart \
  test/local_thumb_cache_test.dart

tagkin_r8_secret_scan

echo "==> D13 regression complete"
