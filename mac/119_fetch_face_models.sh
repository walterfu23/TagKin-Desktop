#!/usr/bin/env bash
# 119_fetch_face_models.sh — Fetch InsightFace buffalo_l ONNX weights for
# on-device face embed (R1). Models are NOT committed — run after clone /
# when likeness matching is needed.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

DEST="${TAGKIN_FACE_MODELS_DIR:-$TAGKIN_DESKTOP_ROOT/assets/models}"
mkdir -p "$DEST"

# Runtime lookup (macOS app cwd is not the repo) — always install here too.
APP_SUPPORT="${HOME}/Library/Application Support/tagkin/models"
mkdir -p "$APP_SUPPORT"

ZIP_URL="${TAGKIN_BUFFALO_URL:-https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip}"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "==> Downloading buffalo_l models → $DEST"
curl -fsSL -o "$TMP/buffalo_l.zip" "$ZIP_URL"
unzip -qo "$TMP/buffalo_l.zip" -d "$TMP/buffalo"

# Layout varies; find the recognizer + detector by name.
find "$TMP/buffalo" -type f -name 'w600k_r50.onnx' -exec cp {} "$DEST/w600k_r50.onnx" \;
find "$TMP/buffalo" -type f -name 'det_10g.onnx' -exec cp {} "$DEST/det_10g.onnx" \;

if [[ ! -f "$DEST/w600k_r50.onnx" ]]; then
  echo "ERROR: w600k_r50.onnx not found in archive" >&2
  find "$TMP/buffalo" -type f -name '*.onnx' >&2 || true
  exit 1
fi

cp "$DEST/w600k_r50.onnx" "$APP_SUPPORT/w600k_r50.onnx"
if [[ -f "$DEST/det_10g.onnx" ]]; then
  cp "$DEST/det_10g.onnx" "$APP_SUPPORT/det_10g.onnx"
fi

echo "==> Installed (repo):"
ls -lh "$DEST"/*.onnx 2>/dev/null || true
echo "==> Installed (runtime host):"
ls -lh "$APP_SUPPORT"/*.onnx 2>/dev/null || true
echo ""
echo "Next: fully quit the app and run ./11_dev.sh (or win equivalent) so Flutter"
echo "bundles assets/models/*.onnx. Hot reload is not enough after a first fetch."
echo "Look for: OnnxFaceEmbedder: loaded asset assets/models/w600k_r50.onnx"
echo "Optional: TAGKIN_FACE_RECOG_MODEL / TAGKIN_FACE_DET_MODEL for custom paths."
echo "License: InsightFace model zoo — review InsightFace license before redistribution."
