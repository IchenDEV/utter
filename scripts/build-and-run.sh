#!/usr/bin/env bash
set -euo pipefail

# Build, bundle, sign, and run the development Utter.app.
# Usage: ./scripts/build-and-run.sh [run|--debug|--logs|--telemetry|--verify]

MODE="${1:-run}"
APP_NAME="Utter"
BUILD_PRODUCT="OpenType"
CLI_HELPER_NAME="opentype-cli"
SUBSYSTEM="com.opentype.voiceinput"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
CLI_HELPER_BINARY="$APP_MACOS/$CLI_HELPER_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_RESOURCES="$ROOT_DIR/Sources/Resources"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build --product "$BUILD_PRODUCT"
swift build --product OpenTypeCLI
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$BUILD_PRODUCT"
CLI_BUILD_BINARY="$BUILD_DIR/OpenTypeCLI"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [ -x "$CLI_BUILD_BINARY" ]; then
  cp "$CLI_BUILD_BINARY" "$CLI_HELPER_BINARY"
  chmod +x "$CLI_HELPER_BINARY"
fi

cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"

for icon in AppIcon.icns AppIconLight.icns AppIconDark.icns; do
  cp "$ICON_RESOURCES/$icon" "$APP_RESOURCES/$icon"
done

for bundle in "$BUILD_DIR"/*.bundle; do
  [ -d "$bundle" ] || continue
  cp -R "$bundle" "$APP_RESOURCES/"
done

# Sign after copying all nested helpers and SwiftPM resource bundles.
ENTITLEMENTS="$ROOT_DIR/Resources/OpenType.entitlements"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  for candidate in "Developer ID Application" "Apple Development" "Utter Signing" "OpenType Signing"; do
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$candidate"; then
      SIGN_IDENTITY="$candidate"
      break
    fi
  done
fi

if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
  codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
fi

icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null || true)"
[ "$icon_file" = "AppIcon" ] || {
  echo "error: development app is missing CFBundleIconFile=AppIcon" >&2
  exit 1
}
[ -s "$APP_RESOURCES/AppIcon.icns" ] || {
  echo "error: development app is missing Contents/Resources/AppIcon.icns" >&2
  exit 1
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$SUBSYSTEM\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      pgrep -x "$APP_NAME" >/dev/null && exit 0
      sleep 0.25
    done
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
