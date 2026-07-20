#!/usr/bin/env bash
# 111_clear_secure_store.sh — wipe D1 Keychain entries for
# service "tagkin.desktop.secure" (FlutterSecureStorage / Clerk session).
#
# Use when macOS keeps prompting for Keychain access, after a bad session,
# or to force a clean sign-in. Safe to re-run (no-op when already empty).
#
# Note: `tagkin.desktop.secure` is the Keychain *service* name; Clerk writes
# several generic-password items under different account names — a single
# `security delete-generic-password -a …` only removes one of them.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

SERVICE="tagkin.desktop.secure"

count_before="$(
  security dump-keychain login.keychain-db 2>/dev/null \
    | grep -c "\"svce\"<blob>=\"${SERVICE}\"" \
    || true
)"
echo "==> Keychain items with service '${SERVICE}': ${count_before}"

if [[ "${count_before}" -eq 0 ]]; then
  echo "==> nothing to delete"
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
echo "==> quit tagkin_desktop fully, then relaunch (Allow / Always Allow once if prompted)"
