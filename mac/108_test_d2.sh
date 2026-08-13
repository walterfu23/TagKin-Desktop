#!/usr/bin/env bash
# 108_test_d2.sh — D2 Library & Item Registry regression: ItemsRepository,
# wide library table (thumb/who/what/where/source), client sort/filter/page,
# processingStatus mapping, detail UI, no-bytes create, R10 tenant isolation,
# §5 mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D2 library)"
flutter test

tagkin_r8_secret_scan

echo "==> integration smoke (library list/detail on macOS)"
flutter test integration_test/items_test.dart -d macos

echo "==> D2 regression complete"
