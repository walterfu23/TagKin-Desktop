#!/usr/bin/env bash
# 111_test_d6.sh — D6 Cost & Usage Surface regression: GET /usage render,
# kill-switch/hard-limit disables ingest, pauseReason surfaced without retry,
# R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D6 usage)"
flutter test

tagkin_r8_secret_scan

echo "==> integration smoke (usage on macOS)"
flutter test integration_test/usage_test.dart -d macos

echo "==> D6 regression complete"
