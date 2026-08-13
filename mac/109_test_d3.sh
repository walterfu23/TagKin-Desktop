#!/usr/bin/env bash
# 109_test_d3.sh — D3 Local Folder Ingest & Batch regression: media
# enumeration + type filtering, content/perceptual hash dedup (incl.
# existing-library check), batch POST /items (refs/hashes only), R10 tenant
# isolation, §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D3 ingest)"
flutter test

tagkin_r8_secret_scan

echo "==> integration smoke (folder ingest on macOS)"
flutter test integration_test/folder_ingest_test.dart -d macos

echo "==> D3 regression complete"
