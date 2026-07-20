#!/usr/bin/env bash
# 105_fetch_ffmpeg.sh — download *static*, arch-native ffmpeg+ffprobe into
# third_party/ffmpeg/macos/ so the .app ships self-contained binaries.
#
# End users never install ffmpeg. Do NOT copy Homebrew bottles here — those
# are dynamically linked to /opt/homebrew and will not run on user machines.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

DEST="${TAGKIN_DESKTOP_ROOT}/third_party/ffmpeg/macos"
mkdir -p "${DEST}"

ARCH="$(uname -m)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "==> downloading static ffmpeg/ffprobe for macOS (${ARCH}) into ${DEST}"

if [[ "${ARCH}" == "arm64" ]]; then
  # Static Apple Silicon builds (osxexperts.net).
  curl -fsSL -o "${TMP}/ffmpeg.zip" "https://www.osxexperts.net/ffmpeg71arm.zip"
  curl -fsSL -o "${TMP}/ffprobe.zip" "https://www.osxexperts.net/ffprobe71arm.zip"
else
  # Static Intel builds (evermeet.cx).
  curl -fsSL -o "${TMP}/ffmpeg.zip" "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip"
  curl -fsSL -o "${TMP}/ffprobe.zip" "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip"
fi

unzip -qo "${TMP}/ffmpeg.zip" -d "${TMP}/ffmpeg_out"
unzip -qo "${TMP}/ffprobe.zip" -d "${TMP}/ffprobe_out"

# Zips may nest the binary; find it.
FFMPEG_BIN="$(find "${TMP}/ffmpeg_out" -type f -name 'ffmpeg' | head -1)"
FFPROBE_BIN="$(find "${TMP}/ffprobe_out" -type f -name 'ffprobe' | head -1)"
if [[ -z "${FFMPEG_BIN}" || -z "${FFPROBE_BIN}" ]]; then
  echo "error: zip did not contain ffmpeg/ffprobe binaries" >&2
  find "${TMP}" -type f >&2 || true
  exit 1
fi

rm -f "${DEST}/ffmpeg" "${DEST}/ffprobe"
cp "${FFMPEG_BIN}" "${DEST}/ffmpeg"
cp "${FFPROBE_BIN}" "${DEST}/ffprobe"
chmod +x "${DEST}/ffmpeg" "${DEST}/ffprobe"

# Reject Homebrew-linked binaries if someone drops them here by mistake.
if otool -L "${DEST}/ffmpeg" 2>/dev/null | grep -q '/opt/homebrew\|/usr/local/Cellar'; then
  echo "error: ${DEST}/ffmpeg links Homebrew dylibs — not redistributable" >&2
  exit 1
fi

# Confirm the binary matches this Mac's CPU.
if ! "${DEST}/ffmpeg" -version >/dev/null 2>&1; then
  echo "error: ${DEST}/ffmpeg is not runnable on this CPU (${ARCH})" >&2
  exit 1
fi

echo "==> installed:"
ls -la "${DEST}/ffmpeg" "${DEST}/ffprobe"
"${DEST}/ffmpeg" -version | head -1
"${DEST}/ffprobe" -version | head -1
echo "==> fetch complete — rebuild the macOS app to embed into Contents/Resources/ffmpeg/"
