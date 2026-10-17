#!/usr/bin/env bash
# Sourced by verify-release-artifact.sh. Needs fail, certificate_sha256, SCRIPT_DIR and the
# REQUIRE_UPDATER, UPDATE_INFO, ALLOW_LOOPBACK_FEED and REQUIRE_DEVELOPER_ID settings.

SPARKLE_COMPONENTS=("Versions/B/Autoupdate" "Versions/B/Updater.app" "")

# Every build embeds the framework because the executable links it, so its layout is always checked.
verify_sparkle_embedding() {
    local app="$1"
    local framework="$app/Contents/Frameworks/Sparkle.framework"
    local executable="$app/Contents/MacOS/Utter"
    local helper="$app/Contents/MacOS/opentype-cli"
    local file loads links

    [ -d "$framework" ] || fail "missing Sparkle.framework in $app"
    [ -z "$(find "$framework" \( -name XPCServices -o -name '*.xpc' \) -print -quit)" ] \
        || fail "Sparkle XPC services must not be bundled in $app"
    while IFS= read -r file; do
        case "$(file -b "$file")" in
            Mach-O*) [ "$(lipo -archs "$file")" = "arm64" ] \
                || fail "Sparkle code must be arm64-only: ${file#"$app"/}" ;;
        esac
    done < <(find "$framework" -type f)
    loads="$(otool -l "$executable")"
    grep -A2 LC_RPATH <<<"$loads" | grep -q 'path @executable_path/../Frameworks ' \
        || fail "Utter executable is missing the Frameworks rpath"
    links="$(otool -L "$helper")"
    if grep -q 'Sparkle' <<<"$links"; then fail "CLI helper must not link Sparkle"; fi

    verify_sparkle_signing "$app"
    if [ "$REQUIRE_UPDATER" = true ]; then
        verify_updater_keys "$app"
        links="$(otool -L "$executable")"
        grep -q '@rpath/Sparkle.framework/' <<<"$links" || fail "Utter executable does not link Sparkle"
    else
        python3 "$SCRIPT_DIR/check-update-plist.py" --app "$app" --forbid \
            || fail "a build that did not ask for updates must carry no update keys: $app"
    fi
}

verify_updater_keys() {
    local app="$1"
    local flags=()
    [ -n "$UPDATE_INFO" ] || fail "--require-updater requires --update-info"
    [ "$ALLOW_LOOPBACK_FEED" = true ] && flags+=(--allow-loopback-feed)
    python3 "$SCRIPT_DIR/check-update-plist.py" --app "$app" --update-info "$UPDATE_INFO" \
        ${flags[@]+"${flags[@]}"} || fail "update keys do not match the committed template: $app"
}

# signer_of PATH — the signing certificate's SHA-256, or "adhoc"; fails when neither can be read.
signer_of() {
    local path="$1" fingerprint signature
    if fingerprint="$(certificate_sha256 "$path")"; then printf '%s\n' "$fingerprint"; return 0; fi
    signature="$(codesign -dvvv "$path" 2>&1)" || return 1
    grep -q '^Signature=adhoc$' <<<"$signature" || return 1
    echo adhoc
}

# Runs for every build, armed or not: a release that ships Sparkle's installer with the app's
# entitlements or a different signer must fail even while the updater is dormant.
verify_sparkle_signing() {
    local app="$1"
    local framework="$app/Contents/Frameworks/Sparkle.framework"
    local app_signer component path signature component_signer entitlements
    app_signer="$(signer_of "$app")" || fail "could not determine how the app is signed"
    if [ "$REQUIRE_UPDATER" = true ] && [ "$app_signer" = adhoc ]; then
        fail "an updater build must be signed with an identity"
    fi
    for component in "${SPARKLE_COMPONENTS[@]}"; do
        path="$framework${component:+/$component}"
        [ -e "$path" ] || fail "missing Sparkle component: ${path#"$app"/}"
        codesign --verify --strict "$path" || fail "invalid signature: ${path#"$app"/}"
        signature="$(codesign -dvvv "$path" 2>&1)"
        grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' <<<"$signature" \
            || fail "Sparkle component lacks the hardened runtime: ${path#"$app"/}"
        component_signer="$(signer_of "$path")" \
            || fail "could not determine how ${path#"$app"/} is signed"
        [ "$component_signer" = "$app_signer" ] \
            || fail "Sparkle component is not signed by the app certificate: ${path#"$app"/}"
        if [ "$REQUIRE_DEVELOPER_ID" = true ]; then
            grep -Eq '^Timestamp=.+$' <<<"$signature" \
                || fail "Sparkle component has no secure timestamp: ${path#"$app"/}"
        fi
        entitlements="$(codesign -d --entitlements - --xml "$path" 2>/dev/null)" \
            || fail "could not read the entitlements of ${path#"$app"/}"
        [ -z "$entitlements" ] || fail "Sparkle component must carry no entitlements: ${path#"$app"/}"
    done
}
