#!/usr/bin/env bash
# 115_test_d9.sh — D9 Person Linking UI regression: suggested→confirm,
# unlink/split/reassign; R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D9 persons)"
flutter test

tagkin_r8_secret_scan

echo "==> integration smoke (persons UI on macOS)"
flutter test integration_test/persons_test.dart -d macos

echo "==> D9 regression complete"
