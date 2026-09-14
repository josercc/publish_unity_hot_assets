#!/usr/bin/env bash
# Shared helpers for Unity Hot Assets desktop packaging.
# Compatible with macOS system Bash 3.2+.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

APP_DISPLAY_NAME="UnityHotAssets"
APP_ID="com.winner.publishUnityHotAssets"
LINUX_BINARY_NAME="publish_unity_hot_assets"
WINDOWS_BINARY_NAME="publish_unity_hot_assets"
MACOS_APP_NAME="publish_unity_hot_assets"

DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
BUILD_NAME="${BUILD_NAME:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

flutter_cmd() {
  if command -v fvm >/dev/null 2>&1 && [ -f "$ROOT_DIR/.fvmrc" ]; then
    fvm flutter "$@"
  else
    flutter "$@"
  fi
}

read_pubspec_version() {
  local raw
  raw="$(grep -E '^version:' "$ROOT_DIR/pubspec.yaml" | head -1 | awk '{print $2}')"
  if [ -z "$BUILD_NAME" ]; then
    BUILD_NAME="${raw%%+*}"
  fi
  if [ -z "$BUILD_NUMBER" ]; then
    case "$raw" in
      *+*) BUILD_NUMBER="${raw##*+}" ;;
      *) BUILD_NUMBER="1" ;;
    esac
  fi
}

ensure_dist() {
  mkdir -p "$DIST_DIR"
}

host_os() {
  case "$(uname -s)" in
    Darwin*) echo "macos" ;;
    Linux*) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

host_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) uname -m ;;
  esac
}

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}
