#!/usr/bin/env bash
# Sourced by build-app.sh. Owns --updates, --update-info and --allow-loopback-feed.
# The caller sets SCRIPT_DIR, PROJECT_DIR, UPDATES, UPDATE_INFO, ALLOW_LOOPBACK_FEED
# and SIGN_IDENTITY.

UPDATE_GATE_FLAGS=()
VERIFY_UPDATER_ARGS=()

update_fail() { echo "error: $1" >&2; exit 1; }

# validate_update_options — refuse bad combinations and lint the plist before the long build.
validate_update_options() {
    if [ "$UPDATES" = true ] && [ -z "$UPDATE_INFO" ]; then
        UPDATE_INFO="${PROJECT_DIR}/Resources/UpdateInfo.plist"
    fi
    if [ "$UPDATES" = false ] && { [ -n "$UPDATE_INFO" ] || [ "$ALLOW_LOOPBACK_FEED" = true ]; }; then
        update_fail "--update-info and --allow-loopback-feed only apply with --updates"
    fi
    [ "$UPDATES" = true ] || return 0
    [ -f "$UPDATE_INFO" ] || update_fail "update info not found: $UPDATE_INFO"
    if [ "$ALLOW_LOOPBACK_FEED" = true ]; then UPDATE_GATE_FLAGS=(--allow-loopback-feed); fi
    python3 "$SCRIPT_DIR/check-update-plist.py" --update-info "$UPDATE_INFO" \
        ${UPDATE_GATE_FLAGS[@]+"${UPDATE_GATE_FLAGS[@]}"} || exit 1
}

# require_updater_identity — an ad-hoc build must never be able to update itself.
require_updater_identity() {
    [ "$UPDATES" = true ] || return 0
    if [ -z "$SIGN_IDENTITY" ] || [ "$SIGN_IDENTITY" = "-" ]; then
        update_fail "--updates needs a real signing identity; an ad-hoc build must never update itself"
    fi
}

# merge_update_keys APP — only a build that asks for updates carries a feed.
merge_update_keys() {
    [ "$UPDATES" = true ] || return 0
    python3 "$SCRIPT_DIR/check-update-plist.py" --update-info "$UPDATE_INFO" \
        --merge-into "$1/Contents/Info.plist" ${UPDATE_GATE_FLAGS[@]+"${UPDATE_GATE_FLAGS[@]}"}
}

# set_updater_verify_args — what verify-release-artifact.sh must additionally require.
set_updater_verify_args() {
    VERIFY_UPDATER_ARGS=()
    [ "$UPDATES" = true ] || return 0
    VERIFY_UPDATER_ARGS=(--require-updater --update-info "$UPDATE_INFO" \
        ${UPDATE_GATE_FLAGS[@]+"${UPDATE_GATE_FLAGS[@]}"})
}
