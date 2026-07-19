#!/usr/bin/env bash
# 11_dev.sh — run the desktop app on macOS (foreground, live console). Band 11-49 = ops.
set -euo pipefail
# shellcheck source=_env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_env.sh"

echo "==> flutter run -d macos"
flutter run -d macos "$@"
