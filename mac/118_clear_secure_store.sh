#!/usr/bin/env bash
# 118_clear_secure_store.sh — wipe the macOS session file and any leftover
# login-Keychain items for service "tagkin.desktop.secure".
#
# The app no longer reads the Keychain. This still deletes old items so a
# later accidental read cannot prompt, and deletes session.json so the next
# launch asks for a sign-in. Safe to re-run.
#
# Note: `tagkin.desktop.secure` is the Keychain *service* name; older builds
# wrote several generic-password items under different account names — a
# single `security delete-generic-password -a …` only removes one of them.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

SERVICE="tagkin.desktop.secure"
SESSION_FILE="${HOME}/Library/Application Support/tagkin_desktop/session.json"

if [[ -f "${SESSION_FILE}" ]]; then
  rm -f "${SESSION_FILE}"
  echo "==> removed ${SESSION_FILE}"
else
  echo "==> no session file"
fi

count_before="$(
  security dump-keychain login.keychain-db 2>/dev/null \
    | grep -c "\"svce\"<blob>=\"${SERVICE}\"" \
    || true
)"
echo "==> Keychain items with service '${SERVICE}': ${count_before}"

if [[ "${count_before}" -eq 0 ]]; then
  echo "==> no Keychain items to delete"
  echo "==> quit FamFace fully, then relaunch"
  exit 0
fi

deleted=0
while security delete-generic-password -s "${SERVICE}" >/dev/null 2>&1; do
  deleted=$((deleted + 1))
  echo "    deleted item ${deleted}"
done

count_after="$(
  security dump-keychain login.keychain-db 2>/dev/null \
    | grep -c "\"svce\"<blob>=\"${SERVICE}\"" \
    || true
)"
echo "==> deleted ${deleted}; remaining: ${count_after}"
echo "==> quit FamFace fully, then relaunch"
