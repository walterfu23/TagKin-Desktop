#!/usr/bin/env bash
# 110_test_d4.sh — D4 Client Pre-pass regression: EXIF when/where, dHash
# confirm, ffmpeg scene detect + adaptive frame sampling (hard cap), stub
# face embed, POST /items/{id}/pre-pass-result payload has no media bytes,
# R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D4 prepass)"
flutter test

tagkin_r8_secret_scan

echo "==> integration smoke (prepass on macOS)"
flutter test integration_test/prepass_test.dart -d macos

echo "==> D4 regression complete"
