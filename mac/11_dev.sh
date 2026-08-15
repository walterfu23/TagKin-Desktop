#!/usr/bin/env bash
# 11_dev.sh — run the desktop app on macOS (foreground, live console). Band 11-49 = ops.
# Always clears the D1 secure store first (clean Clerk session each run).
# Loads CLERK_PUBLISHABLE_KEY / TAGKIN_API_URL from .env and passes them via
# --dart-define (App Sandbox cannot read the repo .env from inside the .app).
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

"${MAC_DIR}/118_clear_secure_store.sh"

ENV_FILE="${TAGKIN_DESKTOP_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    val="${val%$'\r'}"
    val="${val%\"}"
    val="${val#\"}"
    val="${val%\'}"
    val="${val#\'}"
    case "${key}" in
      CLERK_PUBLISHABLE_KEY|TAGKIN_API_URL) export "${key}=${val}" ;;
    esac
  done < "${ENV_FILE}"
fi

if [[ -z "${CLERK_PUBLISHABLE_KEY:-}" ]]; then
  echo "warning: CLERK_PUBLISHABLE_KEY unset — run ./103_clerk-env.sh or create .env" >&2
fi

defines=()
if [[ -n "${CLERK_PUBLISHABLE_KEY:-}" ]]; then
  defines+=(--dart-define="CLERK_PUBLISHABLE_KEY=${CLERK_PUBLISHABLE_KEY}")
fi
if [[ -n "${TAGKIN_API_URL:-}" ]]; then
  defines+=(--dart-define="TAGKIN_API_URL=${TAGKIN_API_URL}")
fi

# So Safari can offer Allow / Always Allow for tagkindesktop:// after Clerk Continue.
DEBUG_APP="${TAGKIN_DESKTOP_ROOT}/build/macos/Build/Products/Debug/tagkin_desktop.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -d "${DEBUG_APP}" && -x "${LSREGISTER}" ]]; then
  echo "==> lsregister ${DEBUG_APP}"
  "${LSREGISTER}" -f "${DEBUG_APP}" || true
fi

echo "==> flutter run -d macos"
flutter run -d macos "${defines[@]}" "$@"
