#!/usr/bin/env bash
# 121_test_d11.sh — D11 Packaging, Signing & Update regression:
# X-TagKin-Client header, warn banner, Update required screen, Settings About;
# R8 / §5 mandatory assertions. Signed Sparkle/MSIX install is operator/CI
# once code-signing certs exist — this bar does not notarize.
# Naming: NNN_test_dN.sh for desktop subsystem regression mac entry points.
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget + D11 client version / update UI)"
flutter test test/api_client_test.dart test/client_version_ui_test.dart

tagkin_r8_secret_scan

echo "==> version stamp (pubspec version is what PackageInfo reports)"
python3 - <<'PY'
from pathlib import Path
text = Path("pubspec.yaml").read_text()
line = next(l for l in text.splitlines() if l.startswith("version:"))
ver = line.split(":", 1)[1].strip()
if not ver or "+" not in ver and "." not in ver:
    raise SystemExit(f"error: pubspec version missing or empty: {line!r}")
print(f"ok: pubspec version {ver}")
PY

echo "==> D11 regression complete"
