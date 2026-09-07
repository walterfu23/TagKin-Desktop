#!/usr/bin/env bash
# 120_branding.sh — regenerate user-facing name + icons from branding/.
# After a rename, stale .app bundles are removed so Dock / lsregister pick up
# the new filename. Native icons need a full relaunch (not hot restart).
set -euo pipefail
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

OLD_NAME="${TAGKIN_DESKTOP_PRODUCT_NAME}"

echo "==> dart run tool/gen_branding.dart"
dart run tool/gen_branding.dart

# Re-read after generate (fileName may have changed).
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

APPICONSET="${TAGKIN_DESKTOP_ROOT}/macos/Runner/Assets.xcassets/AppIcon.appiconset"
if [[ -f "${APPICONSET}/Contents.json" ]]; then
  touch "${APPICONSET}/Contents.json" "${APPICONSET}"/*.png
fi

PRODUCTS="${TAGKIN_DESKTOP_ROOT}/build/macos/Build/Products"
INTERMEDIATES="${TAGKIN_DESKTOP_ROOT}/build/macos/Build/Intermediates.noindex/Runner.build"
rm -rf "${INTERMEDIATES}/Debug/Runner.build/assetcatalog_output" \
  "${INTERMEDIATES}/Release/Runner.build/assetcatalog_output" \
  "${INTERMEDIATES}/Profile/Runner.build/assetcatalog_output"
if [[ -d "${PRODUCTS}" ]]; then
  find "${PRODUCTS}" -name 'AppIcon.icns' -delete 2>/dev/null || true
  find "${PRODUCTS}" -name 'Assets.car' -delete 2>/dev/null || true
  if [[ "${OLD_NAME}" != "${TAGKIN_DESKTOP_PRODUCT_NAME}" ]]; then
    echo "==> bundle filename changed (${OLD_NAME} → ${TAGKIN_DESKTOP_PRODUCT_NAME}); clearing Products"
    rm -rf "${PRODUCTS}"
  else
    # Drop any leftover .app that is not the current product (previous names).
    find "${PRODUCTS}" -maxdepth 3 -name '*.app' | while read -r app; do
      base="$(basename "${app}" .app)"
      if [[ "${base}" != "${TAGKIN_DESKTOP_PRODUCT_NAME}" ]]; then
        echo "==> removing stale ${app}"
        rm -rf "${app}"
      fi
    done
  fi
fi

echo "==> branding complete (${TAGKIN_DESKTOP_PRODUCT_NAME}.app)"
echo "    Pickup: quit the app, then from TagKin-Desktop/mac/ run ./11_dev.sh"
echo "    (full relaunch; hot restart does not refresh Dock icons)."
echo "    Operator GUI: from TagKin/mac/ run ./131_branding-admin.sh"
