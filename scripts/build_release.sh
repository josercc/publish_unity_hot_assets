#!/usr/bin/env bash
# Build and package Unity Hot Assets for the current host OS.
# For all three platforms at once, use GitHub Actions (.github/workflows/release-desktop.yml).
#
# Usage:
#   ./scripts/build_release.sh              # package current OS
#   ./scripts/build_release.sh macos
#   ./scripts/build_release.sh linux
#   ./scripts/build_release.sh linux linux-arm64
#   ./scripts/build_release.sh windows       # requires Windows host / CI
#   BUILD_NAME=1.2.0 BUILD_NUMBER=42 ./scripts/build_release.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

read_pubspec_version
ensure_dist

TARGET="${1:-$(host_os)}"
ARCH_ARG="${2:-}"

log "Unity Hot Assets desktop release packaging"
log "  version: ${BUILD_NAME}+${BUILD_NUMBER}"
log "  target:  ${TARGET}"
log "  dist:    ${DIST_DIR}"

case "$TARGET" in
  macos|darwin)
    [ "$(host_os)" = "macos" ] || die "macOS packages must be built on macOS (or via CI)"
    exec "$SCRIPT_DIR/package_macos.sh" "${ARCH_ARG:-universal}"
    ;;
  linux)
    [ "$(host_os)" = "linux" ] || die "Linux packages must be built on Linux (or via CI)"
    if [ -n "$ARCH_ARG" ]; then
      exec "$SCRIPT_DIR/package_linux.sh" "$ARCH_ARG"
    else
      exec "$SCRIPT_DIR/package_linux.sh"
    fi
    ;;
  windows|win)
    [ "$(host_os)" = "windows" ] || die "Windows packages must be built on Windows (or via CI). On Windows run: .\\scripts\\package_windows.ps1"
    if command -v pwsh >/dev/null 2>&1; then
      exec pwsh -File "$SCRIPT_DIR/package_windows.ps1" ${ARCH_ARG:+-Arch "$ARCH_ARG"}
    else
      exec powershell.exe -File "$SCRIPT_DIR/package_windows.ps1" ${ARCH_ARG:+-Arch "$ARCH_ARG"}
    fi
    ;;
  all)
    die "Building all platforms requires GitHub Actions. Push a tag or run workflow_dispatch on release-desktop.yml"
    ;;
  *)
    die "Unknown target: $TARGET (macos | windows | linux)"
    ;;
esac
