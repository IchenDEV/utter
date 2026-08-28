#!/usr/bin/env bash
# Verify the assembled Utter app and optional DMG. Distribution checks are opt-in.

set -euo pipefail

APP_PATH=""
DMG_PATH=""
EXPECTED_VERSION=""
EXPECTED_CERT_SHA256=""
REQUIRE_DEVELOPER_ID=false
REQUIRE_SELF_SIGNED=false
REQUIRE_NOTARIZATION=false

usage() {
    echo "Usage: $0 --app PATH --version X.Y.Z [--dmg PATH] [--expected-cert-sha256 HEX] [--require-developer-id|--require-self-signed] [--require-notarization]"
}

fail() {
    echo "error: $*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app) APP_PATH="${2:-}"; shift 2 ;;
        --dmg) DMG_PATH="${2:-}"; shift 2 ;;
        --version) EXPECTED_VERSION="${2:-}"; shift 2 ;;
        --expected-cert-sha256) EXPECTED_CERT_SHA256="${2:-}"; shift 2 ;;
        --require-developer-id) REQUIRE_DEVELOPER_ID=true; shift ;;
        --require-self-signed) REQUIRE_SELF_SIGNED=true; shift ;;
        --require-notarization) REQUIRE_NOTARIZATION=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; fail "unknown argument: $1" ;;
    esac
done

[ -n "$APP_PATH" ] || fail "--app is required"
[ -n "$EXPECTED_VERSION" ] || fail "--version is required"
[ -d "$APP_PATH" ] || fail "app bundle not found: $APP_PATH"
validated_version="$("$(dirname "$0")/release-version.sh" "v$EXPECTED_VERSION")" \
    || fail "invalid release version: $EXPECTED_VERSION"
[ "$validated_version" = "$EXPECTED_VERSION" ] || fail "release version changed during validation"
if [ "$REQUIRE_NOTARIZATION" = true ] && [ -z "$DMG_PATH" ]; then
    fail "--require-notarization also requires --dmg"
fi
if [ "$REQUIRE_DEVELOPER_ID" = true ] && [ "$REQUIRE_SELF_SIGNED" = true ]; then
    fail "signing requirements are mutually exclusive"
fi
if [ "$REQUIRE_NOTARIZATION" = true ] && [ "$REQUIRE_DEVELOPER_ID" != true ]; then
    fail "--require-notarization also requires --require-developer-id"
fi
if [ -n "$EXPECTED_CERT_SHA256" ]; then
    EXPECTED_CERT_SHA256="$(tr '[:lower:]' '[:upper:]' <<<"$EXPECTED_CERT_SHA256")"
    [[ "$EXPECTED_CERT_SHA256" =~ ^[A-F0-9]{64}$ ]] \
        || fail "--expected-cert-sha256 must be 64 hexadecimal characters"
fi

certificate_sha256() {
    local app="$1"
    local cert_dir cert_prefix fingerprint
    cert_dir="$(mktemp -d)"
    cert_prefix="$cert_dir/cert"
    if ! codesign -d --extract-certificates="$cert_prefix" "$app" >/dev/null 2>&1; then
        rm -r "$cert_dir"
        return 1
    fi
    if [ ! -s "${cert_prefix}0" ]; then
        rm -r "$cert_dir"
        return 1
    fi
    fingerprint="$(openssl x509 -inform DER -in "${cert_prefix}0" -noout \
        -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr '[:lower:]' '[:upper:]')"
    rm -r "$cert_dir"
    printf '%s\n' "$fingerprint"
}

verify_app() {
    local app="$1"
    local plist="$app/Contents/Info.plist"
    local executable="$app/Contents/MacOS/Utter"
    local helper="$app/Contents/MacOS/opentype-cli"
    local resources="$app/Contents/Resources"
    local product_resources="$resources/OpenType_OpenType.bundle/Contents/Resources"

    [ -f "$plist" ] || fail "missing Info.plist in $app"
    [ -x "$executable" ] || fail "missing executable in $app"
    [ -x "$helper" ] || fail "missing CLI helper in $app"
    [ -s "$resources/Assets.car" ] || fail "missing compiled AppIcon asset catalog in $app"
    find "$resources" -name default.metallib -type f -size +0 -print -quit | grep -q . \
        || fail "missing compiled MLX Metal library in $app"
    [ -s "$product_resources/en.lproj/Localizable.strings" ] \
        || fail "missing English localization in $app"
    [ -s "$product_resources/zh-Hans.lproj/Localizable.strings" ] \
        || fail "missing Simplified Chinese localization in $app"
    [ -f "$product_resources/Sounds/start.caf" ] || fail "missing start sound in $app"
    [ -f "$product_resources/Sounds/stop.caf" ] || fail "missing stop sound in $app"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "com.opentype.voiceinput" ] \
        || fail "unexpected bundle identifier in $app"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$EXPECTED_VERSION" ] \
        || fail "unexpected short version in $app"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$EXPECTED_VERSION" ] \
        || fail "unexpected build version in $app"
    [ "$(lipo -archs "$executable")" = "arm64" ] || fail "Utter executable must be arm64-only"
    [ "$(lipo -archs "$helper")" = "arm64" ] || fail "CLI helper must be arm64-only"
    codesign --verify --deep --strict --verbose=2 "$app"

    if [ "$REQUIRE_DEVELOPER_ID" = true ] || [ "$REQUIRE_SELF_SIGNED" = true ]; then
        local signature
        signature="$(codesign -dvvv "$app" 2>&1)"
        grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' <<<"$signature" \
            || fail "app signature does not enable the hardened runtime"
    fi

    if [ "$REQUIRE_DEVELOPER_ID" = true ]; then
        grep -q '^Authority=Developer ID Application:' <<<"$signature" \
            || fail "app is not signed with a Developer ID Application identity"
        grep -Eq '^TeamIdentifier=[A-Z0-9]+$' <<<"$signature" \
            || fail "app signature has no Apple team identifier"
    fi

    if [ "$REQUIRE_SELF_SIGNED" = true ]; then
        grep -Eq '^Authority=.+$' <<<"$signature" \
            || fail "app has no self-signed authority"
        grep -q '^TeamIdentifier=not set$' <<<"$signature" \
            || fail "self-signed app unexpectedly has an Apple team identifier"
    fi

    if [ -n "$EXPECTED_CERT_SHA256" ]; then
        local actual_cert_sha256
        actual_cert_sha256="$(certificate_sha256 "$app")" \
            || fail "could not extract the app signing certificate"
        [ "$actual_cert_sha256" = "$EXPECTED_CERT_SHA256" ] \
            || fail "app signing certificate does not match the imported certificate"
    fi
}

compare_app_bundles() {
    local expected="$1"
    local actual="$2"
    local relative expected_path actual_path

    diff -u \
        <(cd "$expected" && find . -mindepth 1 -print | LC_ALL=C sort) \
        <(cd "$actual" && find . -mindepth 1 -print | LC_ALL=C sort) \
        || fail "DMG app bundle path manifest differs from the built app"

    while IFS= read -r relative; do
        expected_path="$expected/${relative#./}"
        actual_path="$actual/${relative#./}"
        [ "$(stat -f '%Lp' "$expected_path")" = "$(stat -f '%Lp' "$actual_path")" ] \
            || fail "DMG app bundle permissions differ: $relative"
        if [ -L "$expected_path" ]; then
            [ -L "$actual_path" ] && [ "$(readlink "$expected_path")" = "$(readlink "$actual_path")" ] \
                || fail "DMG app bundle symlink differs: $relative"
        elif [ -f "$expected_path" ]; then
            [ -f "$actual_path" ] && cmp "$expected_path" "$actual_path" \
                || fail "DMG app bundle file differs: $relative"
        elif [ ! -d "$expected_path" ]; then
            fail "unsupported app bundle entry: $relative"
        fi
    done < <(cd "$expected" && find . -mindepth 1 -print | LC_ALL=C sort)
}

verify_app "$APP_PATH"

if [ -n "$DMG_PATH" ]; then
    [ -f "$DMG_PATH" ] || fail "DMG not found: $DMG_PATH"
    hdiutil verify "$DMG_PATH" >/dev/null

    mount_point="$(mktemp -d)"
    mounted=false
    cleanup() {
        if [ "$mounted" = true ]; then
            hdiutil detach "$mount_point" -quiet || true
        fi
        rmdir "$mount_point" 2>/dev/null || true
    }
    trap cleanup EXIT
    hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$mount_point" -quiet
    mounted=true
    verify_app "$mount_point/Utter.app"
    compare_app_bundles "$APP_PATH" "$mount_point/Utter.app"
    hdiutil detach "$mount_point" -quiet
    mounted=false
    rmdir "$mount_point"
    trap - EXIT

    if [ "$REQUIRE_NOTARIZATION" = true ]; then
        xcrun stapler validate "$DMG_PATH"
        spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
        spctl --assess --type execute --verbose=2 "$APP_PATH"
    fi
fi

echo "Release artifact verification passed."
