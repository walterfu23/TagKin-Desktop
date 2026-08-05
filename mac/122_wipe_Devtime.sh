#!/usr/bin/env bash
# 122_wipe_Devtime.sh — DEVELOPMENT ONLY. Wipe desktop residuals so the next
# launch starts from scratch: Clerk/secure session, collections (collections.json),
# prefs, and folder bookmarks under Application Support/tagkin_desktop.
#
# Does NOT delete: user media files, third_party/, face models under
# ~/Library/Application Support/tagkin/models, or API/Postgres data
# (run TagKin/mac/122_wipe_Devtime.sh for the server wipe).
#
# Quit tagkin_desktop fully before running.
#
# Usage:
#   CONFIRM=1 ./122_wipe_Devtime.sh
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

SUPPORT_DIR="${HOME}/Library/Application Support/tagkin_desktop"
SERVICE="tagkin.desktop.secure"

echo "==> 122_wipe_Devtime (desktop) — DEVELOPMENT ONLY"
echo "    Wipes:"
echo "      - Keychain session (${SERVICE})"
echo "      - ${SUPPORT_DIR} (collections.json, prefs, bookmarks, …)"
echo "    Does not delete original media or face models."
echo "    API/Postgres: TagKin/mac/122_wipe_Devtime.sh"
echo ""
echo "    Quit tagkin_desktop fully before continuing."
echo ""

if [[ "${CONFIRM:-}" != "1" ]]; then
  read -r -p "Type y to wipe desktop collections/session/prefs: " ans
  if [[ "${ans}" != "y" && "${ans}" != "Y" ]]; then
    echo "==> aborted"
    exit 1
  fi
fi

echo "==> clearing Keychain service '${SERVICE}'"
deleted=0
while security delete-generic-password -s "${SERVICE}" >/dev/null 2>&1; do
  deleted=$((deleted + 1))
done
echo "    deleted ${deleted} keychain item(s)"

if [[ -d "${SUPPORT_DIR}" ]]; then
  echo "==> removing ${SUPPORT_DIR}"
  rm -rf "${SUPPORT_DIR}"
else
  echo "==> no Application Support dir at ${SUPPORT_DIR}"
fi
mkdir -p "${SUPPORT_DIR}"

echo "==> 122_wipe_Devtime (desktop) complete"
echo "    Next: restart API stack if wiped, then ./11_dev.sh"
