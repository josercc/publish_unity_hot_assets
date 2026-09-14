#!/usr/bin/env bash
# Build Linux release and package as tar.gz (+ optional .deb).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

read_pubspec_version
ensure_dist

TARGET_PLATFORM="${1:-}"
if [ -z "$TARGET_PLATFORM" ]; then
  case "$(host_arch)" in
    arm64) TARGET_PLATFORM="linux-arm64" ;;
    *) TARGET_PLATFORM="linux-x64" ;;
  esac
fi

case "$TARGET_PLATFORM" in
  linux-x64)
    ARCH_LABEL="x64"
    DEB_ARCH="amd64"
    ;;
  linux-arm64)
    ARCH_LABEL="arm64"
    DEB_ARCH="arm64"
    ;;
  *)
    die "Unsupported target platform: $TARGET_PLATFORM (use linux-x64 or linux-arm64)"
    ;;
esac

BUNDLE_DIR="$ROOT_DIR/build/linux/${ARCH_LABEL}/release/bundle"
STAGING="$DIST_DIR/.staging/linux-${ARCH_LABEL}"
TAR_NAME="${APP_DISPLAY_NAME}-${BUILD_NAME}-linux-${ARCH_LABEL}.tar.gz"
DEB_NAME="${APP_DISPLAY_NAME}-${BUILD_NAME}-linux-${DEB_ARCH}.deb"

log "Building Linux release (${TARGET_PLATFORM}, ${BUILD_NAME}+${BUILD_NUMBER})"
flutter_cmd build linux --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER" \
  --target-platform="$TARGET_PLATFORM"

[ -d "$BUNDLE_DIR" ] || die "Missing Linux bundle: $BUNDLE_DIR"
[ -x "$BUNDLE_DIR/$LINUX_BINARY_NAME" ] || die "Missing binary: $BUNDLE_DIR/$LINUX_BINARY_NAME"

rm -rf "$STAGING"
mkdir -p "$STAGING/${APP_DISPLAY_NAME}"
cp -a "$BUNDLE_DIR/." "$STAGING/${APP_DISPLAY_NAME}/"

mkdir -p "$STAGING/${APP_DISPLAY_NAME}/share/applications"
cat > "$STAGING/${APP_DISPLAY_NAME}/share/applications/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Name=${APP_DISPLAY_NAME}
Comment=Unity hot assets publish client
Exec=${LINUX_BINARY_NAME}
Icon=${APP_ID}
Terminal=false
Type=Application
Categories=Development;
StartupWMClass=${LINUX_BINARY_NAME}
EOF

log "Creating tarball: $TAR_NAME"
tar -C "$STAGING" -czf "$DIST_DIR/$TAR_NAME" "$APP_DISPLAY_NAME"

if command -v dpkg-deb >/dev/null 2>&1; then
  log "Creating Debian package: $DEB_NAME"
  DEB_ROOT="$DIST_DIR/.staging/deb-${ARCH_LABEL}"
  rm -rf "$DEB_ROOT"
  mkdir -p "$DEB_ROOT/DEBIAN"
  mkdir -p "$DEB_ROOT/usr/lib/${APP_ID}"
  mkdir -p "$DEB_ROOT/usr/bin"
  mkdir -p "$DEB_ROOT/usr/share/applications"
  mkdir -p "$DEB_ROOT/usr/share/doc/${APP_ID}"

  cp -a "$BUNDLE_DIR/." "$DEB_ROOT/usr/lib/${APP_ID}/"
  ln -sf "../lib/${APP_ID}/${LINUX_BINARY_NAME}" "$DEB_ROOT/usr/bin/${LINUX_BINARY_NAME}"

  cat > "$DEB_ROOT/usr/share/applications/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Name=${APP_DISPLAY_NAME}
Comment=Unity hot assets publish client
Exec=${LINUX_BINARY_NAME}
Icon=${APP_ID}
Terminal=false
Type=Application
Categories=Development;
StartupWMClass=${LINUX_BINARY_NAME}
EOF

  cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: ${APP_ID}
Version: ${BUILD_NAME}-${BUILD_NUMBER}
Section: devel
Priority: optional
Architecture: ${DEB_ARCH}
Maintainer: Winner <noreply@winner.com>
Description: Unity hot assets publish client
 Desktop client for publishing Unity hot assets (macOS / Windows / Linux).
Depends: libgtk-3-0, libblkid1, liblzma5
EOF

  cat > "$DEB_ROOT/usr/share/doc/${APP_ID}/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ${APP_DISPLAY_NAME}
Copyright: 2026 Winner
License: proprietary
EOF

  dpkg-deb --build --root-owner-group "$DEB_ROOT" "$DIST_DIR/$DEB_NAME"
  rm -rf "$DEB_ROOT"
else
  log "dpkg-deb not found; skipping .deb (tarball only)"
fi

rm -rf "$STAGING"
log "Linux packages ready under $DIST_DIR"
ls -lh "$DIST_DIR"/"${APP_DISPLAY_NAME}-${BUILD_NAME}-linux-"* 2>/dev/null || true
