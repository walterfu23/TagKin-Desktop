#!/usr/bin/env bash
# 101_setup.sh — first-clone setup: fetch Dart deps + generate contract models
# + embeddable ffmpeg binaries for D4 (shipped inside the app; end users never
# install ffmpeg).
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

echo "==> bundled ffmpeg for D4 (app-shipped; not a user install step)"
"${MAC_DIR}/105_fetch_ffmpeg.sh"

echo "==> setup complete"
