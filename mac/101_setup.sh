#!/usr/bin/env bash
# 101_setup.sh — first-clone setup: fetch Dart deps + generate contract models.
# Run once after cloning, or after a Flutter/toolchain change.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter --version"
flutter --version
echo "==> flutter pub get"
flutter pub get
echo "==> contract codegen"
"${MAC_DIR}/102_codegen.sh"
echo "==> setup complete"
