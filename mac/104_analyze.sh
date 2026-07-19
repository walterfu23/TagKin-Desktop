#!/usr/bin/env bash
# 104_analyze.sh — static analysis bar (flutter analyze). Keep zero analyzer issues.
set -euo pipefail
# shellcheck source=_env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_env.sh"

echo "==> flutter analyze"
flutter analyze
echo "==> analyze complete"
