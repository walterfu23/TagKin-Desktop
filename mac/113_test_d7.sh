#!/usr/bin/env bash
# 113_test_d7.sh — D7 Tagging & Jobs Lifecycle regression: analyze, job progress,
# cancel, delete; R10/R1/R5/R8/R9 §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D7 jobs)"
flutter test

tagkin_r8_secret_scan

echo "==> integration smoke (jobs lifecycle on macOS)"
flutter test integration_test/jobs_lifecycle_test.dart -d macos

echo "==> D7 regression complete"
