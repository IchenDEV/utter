#!/usr/bin/env bash
#
# build-app.sh — Build the medical offline app and package it as a DMG.
#
# Uses xcodebuild (not bare swift build) so that Metal shaders required
# by mlx-swift are compiled into default.metallib.
#
# Usage:
#   ./scripts/build-app.sh              # build .app + .dmg
#   ./scripts/build-app.sh --app-only   # build .app only
#   ./scripts/build-app.sh --offline-model-root=/path/to/models
#   ./scripts/build-app.sh --help       # show help
#
# Requirements:
#   - macOS with Xcode (full install, not just CLI tools)
#   - Swift 6.0+
#

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────────

APP_NAME="Utter Medical Offline"
BUILD_PRODUCT="OpenType"
SCHEME_NAME="OpenType"
BUNDLE_ID="com.opentype.voiceinput.medical-offline"
DMG_NAME="Utter-Medical-Offline"
# Default: use latest git tag (strip leading "v"), fallback to 0.0.0-dev
if [ -z "${VERSION:-}" ]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0-dev")"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DERIVED_DATA="${PROJECT_DIR}/.build/xcode"
BUILD_DIR="${DERIVED_DATA}/Build/Products/Release"
DIST_DIR="${PROJECT_DIR}/dist"
APP_ONLY=false
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
OFFLINE_MODEL_ROOT=""

# ─── Parse arguments ────────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --app-only)  APP_ONLY=true ;;
        --offline-model-root=*) OFFLINE_MODEL_ROOT="${arg#*=}" ;;
        --version=*) VERSION="${arg#*=}" ;;
        --sign=*)    SIGN_IDENTITY="${arg#*=}" ;;
        --help|-h)
            echo "Usage: $0 [--version=X.Y.Z] [--app-only] [--sign=IDENTITY] [--offline-model-root=PATH] [--help]"
            echo ""
            echo "  --version=X.Y.Z    Set version (default: latest git tag, or \$VERSION env)"
            echo "  --app-only         Build .app bundle only, skip DMG creation"
            echo "  --sign=IDENTITY    Code signing identity (default: auto-detect)"
            echo "                     Use '--sign=-' to force ad-hoc signing"
            echo "  --offline-model-root=PATH"
            echo "                     Bundle PATH/speech and PATH/formatting"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${DMG_NAME}-${VERSION}.dmg"

# ─── Helpers ────────────────────────────────────────────────────────────────────

step() { echo ""; echo "▶ $1"; }
done_msg() { echo "  ✓ $1"; }

# ─── Step 1: Build with xcodebuild (Universal Binary) ─────────────────────────

step "Building ${APP_NAME} (Release, arm64)…"
cd "${PROJECT_DIR}"
xcodebuild \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA}" \
    -destination 'platform=macOS' \
    ARCHS="arm64" \
    ONLY_ACTIVE_ARCH=NO \
    build \
    -quiet
done_msg "Build succeeded"

# ─── Step 2: Assemble .app bundle ───────────────────────────────────────────────

step "Assembling ${APP_NAME}.app…"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Binary
cp "${BUILD_DIR}/${BUILD_PRODUCT}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Info.plist (with version injected)
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}"           "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}"       "${APP_BUNDLE}/Contents/Info.plist"

# PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Copy ALL resource bundles produced by xcodebuild (includes Metal shaders)
for bundle in "${BUILD_DIR}"/*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "${APP_BUNDLE}/Contents/Resources/"
done

if [ -n "$OFFLINE_MODEL_ROOT" ]; then
    step "Bundling fixed offline models…"
    OFFLINE_MODEL_ROOT="$(cd "$OFFLINE_MODEL_ROOT" && pwd)"
    "${SCRIPT_DIR}/verify-offline-model-bundle.sh" "$OFFLINE_MODEL_ROOT" --source

    OFFLINE_DEST="${APP_BUNDLE}/Contents/Resources/OfflineModels"
    mkdir -p "${OFFLINE_DEST}/speech" "${OFFLINE_DEST}/speech-runtime" "${OFFLINE_DEST}/formatting"
    cp -R "${OFFLINE_MODEL_ROOT}/speech/." "${OFFLINE_DEST}/speech/"
    cp -R "${OFFLINE_MODEL_ROOT}/speech-runtime/." "${OFFLINE_DEST}/speech-runtime/"
    cp -R "${OFFLINE_MODEL_ROOT}/formatting/." "${OFFLINE_DEST}/formatting/"
    cp -R "${OFFLINE_MODEL_ROOT}/LICENSES" "${OFFLINE_DEST}/LICENSES"
    cp "${OFFLINE_MODEL_ROOT}/NOTICE" "${OFFLINE_DEST}/NOTICE"
    cp "${PROJECT_DIR}/Sources/Resources/OfflineModelManifest.json" "${OFFLINE_DEST}/manifest.json"
    (
        cd "$OFFLINE_DEST"
        find manifest.json NOTICE LICENSES speech speech-runtime formatting -type f -print0 \
            | LC_ALL=C sort -z \
            | xargs -0 shasum -a 256 > SHA256SUMS
    )
    "${SCRIPT_DIR}/verify-offline-model-bundle.sh" "$OFFLINE_DEST"
    done_msg "Offline models and SHA-256 manifest bundled"
fi

done_msg "App bundle assembled"

# ─── Step 3: Build AppIcon asset catalog (system appearances) ───────────────────

step "Building AppIcon asset catalog (system appearances)…"

ICON_RESOURCE_DIR="${PROJECT_DIR}/Sources/Resources"
ICON_WORK_DIR="${PROJECT_DIR}/.build/AppIcon.work"
ICON_COMPOSER_DIR="${ICON_RESOURCE_DIR}/AppIcon.icon"
ACTOOL_OUT_DIR="${ICON_WORK_DIR}/compiled"

rm -rf "${ICON_WORK_DIR}"
mkdir -p "${ACTOOL_OUT_DIR}"

xcrun actool "${ICON_COMPOSER_DIR}" \
    --compile "${ACTOOL_OUT_DIR}" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --include-all-app-icons \
    --output-partial-info-plist "${ICON_WORK_DIR}/Assets-partial.plist" \
    --output-format human-readable-text \
    >/dev/null

cp "${ACTOOL_OUT_DIR}/Assets.car" "${APP_BUNDLE}/Contents/Resources/"
cp "${ACTOOL_OUT_DIR}/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Keep .icns files for Finder/LaunchServices and for the in-app preview in
# AboutView/SettingsView, which read these via Bundle.
cp "${ICON_RESOURCE_DIR}/AppIconLight.icns" "${APP_BUNDLE}/Contents/Resources/AppIconLight.icns"
cp "${ICON_RESOURCE_DIR}/AppIconDark.icns" "${APP_BUNDLE}/Contents/Resources/AppIconDark.icns"
done_msg "AppIcon compiled to Assets.car (system appearances)"

# ─── Step 4: Code sign ───────────────────────────────────────────────────────

step "Code signing (hardened runtime + entitlements)…"

ENTITLEMENTS="${PROJECT_DIR}/Resources/OpenType.entitlements"

if [ -z "$SIGN_IDENTITY" ]; then
    for candidate in "Developer ID Application" "Apple Development" "Utter Signing" "OpenType Signing"; do
        if security find-identity -v -p codesigning 2>/dev/null | grep -q "$candidate"; then
            SIGN_IDENTITY="$candidate"
            break
        fi
    done
fi

SIGN_FLAGS=(--force --options runtime --entitlements "$ENTITLEMENTS")

EFFECTIVE_SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NESTED_SIGN_FLAGS=(--force)
if [ "$EFFECTIVE_SIGN_IDENTITY" != "-" ]; then
    NESTED_SIGN_FLAGS+=(--options runtime)
fi

# Resource-hosted runtimes are not nested bundles, so sign every embedded
# Mach-O before sealing the outer app.
while IFS= read -r -d '' nested_code; do
    if [ "$nested_code" = "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" ]; then
        continue
    fi
    if file -b "$nested_code" | grep -q 'Mach-O'; then
        codesign "${NESTED_SIGN_FLAGS[@]}" --sign "$EFFECTIVE_SIGN_IDENTITY" "$nested_code"
    fi
done < <(find "${APP_BUNDLE}/Contents" -type f -print0)

SIGNED_OFFLINE_ROOT="${APP_BUNDLE}/Contents/Resources/OfflineModels"
if [ -d "$SIGNED_OFFLINE_ROOT" ]; then
    (
        cd "$SIGNED_OFFLINE_ROOT"
        find manifest.json NOTICE LICENSES speech speech-runtime formatting -type f -print0 \
            | LC_ALL=C sort -z \
            | xargs -0 shasum -a 256 > SHA256SUMS
    )
    "${SCRIPT_DIR}/verify-offline-model-bundle.sh" "$SIGNED_OFFLINE_ROOT"
    done_msg "Embedded runtime signatures included in SHA-256 manifest"
fi

if [ "$EFFECTIVE_SIGN_IDENTITY" != "-" ]; then
    codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "${APP_BUNDLE}"
    done_msg "Signed with: $SIGN_IDENTITY (hardened runtime)"
else
    codesign "${SIGN_FLAGS[@]}" --sign - "${APP_BUNDLE}"
    done_msg "Signed (ad-hoc, hardened runtime)"
    echo "  ⚠ Ad-hoc signing: first launch on other machines may require:"
    echo "    xattr -cr '${APP_NAME}.app'"
fi

# ─── Step 5: Create DMG ────────────────────────────────────────────────────────

if [ "$APP_ONLY" = true ]; then
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Done!  ${APP_BUNDLE}"
    echo "═══════════════════════════════════════════════════"
    exit 0
fi

step "Creating DMG…"

rm -f "${DMG_PATH}"

DMG_TMP="${DIST_DIR}/.dmg-staging"
rm -rf "${DMG_TMP}"
mkdir -p "${DMG_TMP}"

cp -R "${APP_BUNDLE}" "${DMG_TMP}/"
ln -s /Applications "${DMG_TMP}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_TMP}" \
    -ov -format UDZO \
    "${DMG_PATH}" \
    -quiet

rm -rf "${DMG_TMP}"

done_msg "DMG created"

# ─── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════"
echo "  App:  ${APP_BUNDLE}"
echo "  DMG:  ${DMG_PATH}"
echo ""
echo "  To install: open ${DMG_PATH}"
echo "═══════════════════════════════════════════════════"
