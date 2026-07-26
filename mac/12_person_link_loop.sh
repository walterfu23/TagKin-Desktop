#!/usr/bin/env bash
# 12_person_link_loop.sh — Delete suggested persons, re-analyze N photos, check
# Persons consolidation; repeat up to TAGKIN_LOOP_MAX (default 20).
#
# Required env:
#   TAGKIN_API_TOKEN       Bearer JWT from a logged-in desktop/API session
#   TAGKIN_LOOP_ITEM_IDS   comma-separated photo item UUIDs (typically 3)
#
# Optional:
#   TAGKIN_API_URL                    default http://localhost:8787
#   TAGKIN_LOOP_MAX                   default 20
#
# Success: one suggested person has appearances on every loop item (cross-item
# consolidation). Extra suggested persons from other faces in group shots OK.
#
# Prerequisites: API stack up, Gemini configured, face ONNX via 117_fetch_face_models.sh.
# Does not confirm persons (R6). Never commits tokens.
#
# Note: macOS App Sandbox cannot write the shell's /tmp status file. The Dart
# tool prints PERSON_LINK_LOOP_RESULT:ok|fail|error for this wrapper to parse.
set -euo pipefail
# shellcheck source=_env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_env.sh"

if [[ -z "${TAGKIN_API_TOKEN:-}" ]]; then
  echo "error: TAGKIN_API_TOKEN is required (Bearer JWT)." >&2
  exit 2
fi
if [[ -z "${TAGKIN_LOOP_ITEM_IDS:-}" ]]; then
  echo "error: TAGKIN_LOOP_ITEM_IDS is required (comma-separated item UUIDs)." >&2
  exit 2
fi

export TAGKIN_API_URL="${TAGKIN_API_URL:-http://localhost:8787}"
MAX="${TAGKIN_LOOP_MAX:-20}"

# Sandbox-writable fallback (same container as the macOS app).
APP_STATUS="${HOME}/Library/Containers/com.tagkin.tagkinDesktop/Data/Library/Application Support/com.tagkin.tagkinDesktop/person_link_loop.status"

echo "==> person link loop (max $MAX iterations)"
echo "    API=$TAGKIN_API_URL"
echo "    items=$TAGKIN_LOOP_ITEM_IDS"
echo "    success=cross-item person covering all items"

for ((i = 1; i <= MAX; i++)); do
  echo ""
  echo "======== iteration $i / $MAX ========"
  rm -f "$APP_STATUS"
  LOG="$(mktemp -t tagkin_person_link_loop_log.XXXXXX)"
  set +e
  # shellcheck disable=SC2094
  flutter run -d macos -t tool/person_link_loop.dart --quiet 2>&1 | tee "$LOG"
  flutter_ec=${PIPESTATUS[0]}
  set -e

  status=""
  if grep -q 'PERSON_LINK_LOOP_RESULT:ok' "$LOG" 2>/dev/null; then
    status="$(grep 'PERSON_LINK_LOOP_RESULT:ok' "$LOG" | tail -1)"
  elif grep -q 'PERSON_LINK_LOOP_RESULT:fail' "$LOG" 2>/dev/null; then
    status="$(grep 'PERSON_LINK_LOOP_RESULT:fail' "$LOG" | tail -1)"
  elif grep -q 'PERSON_LINK_LOOP_RESULT:error' "$LOG" 2>/dev/null; then
    status="$(grep 'PERSON_LINK_LOOP_RESULT:error' "$LOG" | tail -1)"
  elif [[ -f "$APP_STATUS" ]]; then
    status="$(cat "$APP_STATUS")"
  else
    status="missing-status"
  fi
  rm -f "$LOG"

  echo "    status: $status (flutter_exit=$flutter_ec)"

  if [[ "$status" == PERSON_LINK_LOOP_RESULT:ok* || "$status" == ok* ]]; then
    echo "==> SUCCESS on iteration $i"
    exit 0
  fi

  if [[ "$status" == PERSON_LINK_LOOP_RESULT:error* || "$status" == error* || "$status" == missing-status ]]; then
    echo "==> hard error on iteration $i — stopping" >&2
    echo "    tip: token expires ~60s — click the key icon, re-export TAGKIN_API_TOKEN, re-run." >&2
    exit 2
  fi

  echo "==> iteration $i did not consolidate — continuing"
  echo "    tip: if the next iter 401s, refresh TAGKIN_API_TOKEN (key icon) first."
done

echo "==> gave up after $MAX iterations" >&2
exit 1
