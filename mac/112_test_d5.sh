#!/usr/bin/env bash
# 112_test_d5.sh — D5 Ingest Upload & Grants regression: upload-grant URL only,
# direct model-host PUT (never tagkin-api), analysisRef recording + expiry retry,
# R10/R1/R5/R8 §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D5 upload)"
flutter test

tagkin_r8_secret_scan

echo "==> integration smoke (upload on macOS)"
flutter test integration_test/upload_test.dart -d macos

echo "==> D5 regression complete"
