#!/usr/bin/env bash
# Sourced by build-app.sh and build-and-run.sh. Embeds the pinned Sparkle framework in an
# assembled Utter.app, thins it to arm64, and signs its nested code without entitlements.

SPARKLE_RPATH="@executable_path/../Frameworks"

# find_sparkle_framework ARTIFACTS_DIR — the framework slice SwiftPM fetched from the pinned release.
find_sparkle_framework() {
    local artifacts="$1" found
    found="$(find "$artifacts/sparkle/Sparkle/Sparkle.xcframework" -type d -name Sparkle.framework \
        -path '*/macos-*/*' 2>/dev/null | head -n 1)"
    [ -n "$found" ] || { echo "error: Sparkle.framework not found under $artifacts" >&2; return 1; }
    printf '%s\n' "$found"
}

# sparkle_machos FRAMEWORK — every Mach-O file the framework ships once XPCServices are removed.
sparkle_machos() {
    local framework="$1"
    printf '%s\n' "$framework/Versions/B/Sparkle" "$framework/Versions/B/Autoupdate" \
        "$framework/Versions/B/Updater.app/Contents/MacOS/Updater"
}

# embed_sparkle APP FRAMEWORK_SOURCE — run before any signing: the rpath edit invalidates a signature.
embed_sparkle() {
    local app="$1" source="$2"
    local framework="$app/Contents/Frameworks/Sparkle.framework"
    local executable="$app/Contents/MacOS/Utter"
    local file thin mode license="${source%%/Sparkle.xcframework/*}/LICENSE"
    [ -s "$license" ] || { echo "error: pinned Sparkle LICENSE not found: $license" >&2; return 1; }
    mkdir -p "$app/Contents/Frameworks"
    rm -rf "$framework"
    ditto "$source" "$framework"
    cp "$license" "$framework/Versions/B/Resources/LICENSE"
    rm -rf "$framework/Versions/B/XPCServices" "$framework/XPCServices"
    while IFS= read -r file; do
        [ -f "$file" ] || { echo "error: Sparkle code missing from the framework: $file" >&2; return 1; }
        if [ "$(lipo -archs "$file")" != "arm64" ]; then
            thin="$file.arm64"
            mode="$(stat -f '%Lp' "$file")"
            lipo -thin arm64 -output "$thin" "$file"
            chmod "$mode" "$thin"
            mv "$thin" "$file"
        fi
    done < <(sparkle_machos "$framework")
    if ! otool -l "$executable" | grep -A2 LC_RPATH | grep -q "path $SPARKLE_RPATH "; then
        install_name_tool -add_rpath "$SPARKLE_RPATH" "$executable"
    fi
}

# sign_sparkle APP IDENTITY [CODESIGN_FLAGS...] — inside out, hardened runtime, no entitlements.
# `--deep` on the app would give Autoupdate, which replaces the installed app, the app's
# JIT, unsigned-memory and library-validation-off entitlements.
sign_sparkle() {
    local app="$1" identity="$2"
    shift 2
    local framework="$app/Contents/Frameworks/Sparkle.framework"
    local flags=(--force --options runtime "$@")
    codesign "${flags[@]}" --sign "$identity" "$framework/Versions/B/Autoupdate"
    codesign "${flags[@]}" --sign "$identity" "$framework/Versions/B/Updater.app"
    codesign "${flags[@]}" --sign "$identity" "$framework"
}
