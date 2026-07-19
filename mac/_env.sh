#!/usr/bin/env bash
# Shared Mac helper for TagKin-Desktop/mac/*.sh — source this; do not run directly.
# Sets the desktop repo root + ensures the Flutter SDK is on PATH.

set -euo pipefail

_TAGKIN_DESKTOP_MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAGKIN_DESKTOP_ROOT="$(cd "${_TAGKIN_DESKTOP_MAC_DIR}/.." && pwd)"
cd "${TAGKIN_DESKTOP_ROOT}"

# Common Flutter install locations (Homebrew, manual clone, fvm). Extend as needed.
export PATH="${TAGKIN_DESKTOP_ROOT}/.fvm/flutter_sdk/bin:${HOME}/development/flutter/bin:${HOME}/flutter/bin:/opt/homebrew/bin:${PATH}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: flutter not found on PATH." >&2
  echo "       Install the Flutter stable SDK (https://docs.flutter.dev/get-started/install/macos)" >&2
  echo "       or add its bin/ to PATH, then re-run." >&2
  exit 1
fi

# Ensure desktop is enabled (idempotent, cheap).
flutter config --enable-macos-desktop >/dev/null 2>&1 || true
