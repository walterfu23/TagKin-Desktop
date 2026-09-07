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

# User-facing bundle filename from branding/branding.yaml (generated xcconfig).
TAGKIN_DESKTOP_PRODUCT_NAME="tagkin_desktop"
_BRANDING_XCCONFIG="${TAGKIN_DESKTOP_ROOT}/macos/Runner/Configs/Branding.xcconfig"
if [[ -f "${_BRANDING_XCCONFIG}" ]]; then
  TAGKIN_DESKTOP_PRODUCT_NAME="$(
    awk -F= '/^PRODUCT_NAME[[:space:]]*=/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }' "${_BRANDING_XCCONFIG}"
  )"
  if [[ -z "${TAGKIN_DESKTOP_PRODUCT_NAME}" ]]; then
    TAGKIN_DESKTOP_PRODUCT_NAME="tagkin_desktop"
  fi
fi
export TAGKIN_DESKTOP_PRODUCT_NAME

# R8: no long-lived secrets in client source. Used by NNN_test_dN bars and CI.
tagkin_r8_secret_scan() {
  echo "==> R8 secret scan (lib/ must not contain sk_test_/sk_live_/CLERK_SECRET_KEY)"
  if grep -R -n -E 'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY' lib/ >/dev/null 2>&1; then
    echo "error: forbidden secret pattern found under lib/" >&2
    grep -R -n -E 'sk_test_|sk_live_|CLERK_SECRET_KEY|GEMINI_API_KEY' lib/ >&2 || true
    exit 1
  fi
}
