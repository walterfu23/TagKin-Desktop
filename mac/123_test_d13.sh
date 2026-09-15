#!/usr/bin/env bash
# 123_test_d13.sh — D13 Item List Export regression: Views dropdown, reorder,
# JSON / FCP7 XML / FCPXML / MP4-with-music export, R10/R1/R5/R8 §5
# mandatory assertions.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D13 item list export)"
flutter test test/item_lists test/d13_trust_boundary_test.dart \
  test/local_thumb_cache_test.dart test/sharpness_test.dart \
  test/prepass/sharpness_score_chip_test.dart

tagkin_r8_secret_scan

echo "==> D13 vendor-name scan (R8 — client must not name music vendors)"
if grep -R -n -E 'ElevenLabs|Mubert|Loudly|AIVA|Soundraw|ELEVENLABS_API_KEY' lib/ assets/ >/dev/null 2>&1; then
  echo "error: music vendor name or key found under lib/ or assets/" >&2
  grep -R -n -E 'ElevenLabs|Mubert|Loudly|AIVA|Soundraw|ELEVENLABS_API_KEY' lib/ assets/ >&2 || true
  exit 1
fi

echo "==> D13 regression complete"
