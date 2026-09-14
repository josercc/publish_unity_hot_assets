#!/usr/bin/env bash
# Build macOS release (.app) and package as DMG + ZIP (Intel + Apple Silicon).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

read_pubspec_version
ensure_dist

ARCH_LABEL="${1:-universal}"
STAGING="$DIST_DIR/.staging/macos"
DMG_NAME="${APP_DISPLAY_NAME}-${BUILD_NAME}-macos-${ARCH_LABEL}.dmg"
ZIP_NAME="${APP_DISPLAY_NAME}-${BUILD_NAME}-macos-${ARCH_LABEL}.zip"

log "Building macOS release (${BUILD_NAME}+${BUILD_NUMBER})"
flutter_cmd build macos --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

APP_PATH="$ROOT_DIR/build/macos/Build/Products/Release/${MACOS_APP_NAME}.app"
[ -d "$APP_PATH" ] || die "Missing app bundle: $APP_PATH"

BIN="$APP_PATH/Contents/MacOS/$MACOS_APP_NAME"
if command -v lipo >/dev/null 2>&1 && [ -f "$BIN" ]; then
  log "Binary architectures: $(lipo -archs "$BIN" 2>/dev/null || echo unknown)"
fi

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

log "Creating ZIP: $ZIP_NAME"
(
  cd "$STAGING"
  ditto -c -k --sequesterRsrc --keepParent "${MACOS_APP_NAME}.app" "$DIST_DIR/$ZIP_NAME"
)

log "Creating DMG: $DMG_NAME"
TMP_DMG="$DIST_DIR/.${DMG_NAME}.tmp.dmg"
rm -f "$TMP_DMG" "$DIST_DIR/$DMG_NAME"

hdiutil create \
  -volname "$APP_DISPLAY_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$TMP_DMG"

mv "$TMP_DMG" "$DIST_DIR/$DMG_NAME"
rm -rf "$STAGING"

log "macOS packages ready:"
log "  $DIST_DIR/$DMG_NAME"
log "  $DIST_DIR/$ZIP_NAME"
