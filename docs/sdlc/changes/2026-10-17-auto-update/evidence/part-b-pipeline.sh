#!/usr/bin/env bash
#
# Release-style pipeline evidence for Part B, run against a local build produced
# with a throwaway self-signed identity:
#
#   PATH=<rehearsal>/bin:$PATH bash scripts/build-app.sh --updates --version=X.Y.Z \
#       --sign="Utter Rehearsal Signing"
#
# It verifies the armed app and DMG, dumps the app plist out of the mounted DMG,
# generates and signs the appcast from it, and independently verifies both
# signatures against the public key committed in Resources/UpdateInfo.plist.
#
# usage: part-b-pipeline.sh [VERSION]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
TOOLS="${SPARKLE_TOOLS_BIN:-$ROOT/.build/artifacts/sparkle/Sparkle/bin}"
VERSION="${1:-0.0.56}"
APP="$ROOT/dist/Utter.app"
DMG="$ROOT/dist/Utter-$VERSION.dmg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -d "$APP" ] || { echo "missing $APP" >&2; exit 1; }
[ -f "$DMG" ] || { echo "missing $DMG" >&2; exit 1; }

PUBLIC="$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["SUPublicEDKey"])' \
    "$ROOT/Resources/UpdateInfo.plist")"

# 1. The release verifier, in the mode the workflow uses, plus the app plist
#    taken from inside the mounted DMG.
"$ROOT/scripts/verify-release-artifact.sh" \
    --app "$APP" --dmg "$DMG" --version "$VERSION" \
    --require-updater --update-info "$ROOT/Resources/UpdateInfo.plist" \
    --require-self-signed --dump-app-plist "$WORK/dmg-app-Info.plist" \
    > "$WORK/verify.log" 2>&1

# The dumped plist must be the mounted DMG's app, not a second copy.
cmp "$WORK/dmg-app-Info.plist" "$APP/Contents/Info.plist"

# 2. The appcarries exactly the committed keys.
python3 "$ROOT/scripts/check-update-plist.py" --app "$APP" \
    --update-info "$ROOT/Resources/UpdateInfo.plist" >/dev/null

# 3. The appcast, signed with the keychain key, then independently verified.
printf '%s\n' '- Evidence fixture' > "$WORK/notes.txt"
DMG_SIGNATURE="$("$TOOLS/sign_update" -p "$DMG")"
python3 "$ROOT/scripts/generate-appcast.py" \
    --tag "v$VERSION" --version "$VERSION" \
    --app-plist "$WORK/dmg-app-Info.plist" --dmg "$DMG" \
    --signature "$DMG_SIGNATURE" --release-notes "$WORK/notes.txt" \
    --pub-date "Sat, 17 Oct 2026 12:00:00 +0000" \
    --output "$WORK/appcast.xml" > "$WORK/appcast.log" 2>&1
"$TOOLS/sign_update" "$WORK/appcast.xml" > "$WORK/sign-feed.log" 2>&1

"$ROOT/scripts/verify-update-signature.swift" --public-key "$PUBLIC" \
    --dmg "$DMG" --signature "$DMG_SIGNATURE" > "$WORK/verify-dmg.log" 2>&1
"$ROOT/scripts/verify-update-signature.swift" --public-key "$PUBLIC" \
    --feed "$WORK/appcast.xml" > "$WORK/verify-feed.log" 2>&1

# 4. Nested Sparkle facts on the real artifact.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
AUTOUPDATE="$FRAMEWORK/Versions/B/Autoupdate"
autoupdate_signature="$(codesign -dvvv "$AUTOUPDATE" 2>&1)"
autoupdate_entitlements="$(codesign -d --entitlements - --xml "$AUTOUPDATE" 2>/dev/null || true)"

cat <<JSON
{
  "version": "$VERSION",
  "verifier": "pass (--require-updater, --require-self-signed, --dump-app-plist)",
  "dmg_app_plist_equals_built_app": true,
  "carried_keys": "$(python3 -c 'import plistlib,sys; print(" ".join(sorted(k for k in plistlib.load(open(sys.argv[1],"rb")) if k.startswith("SU"))))' "$WORK/dmg-app-Info.plist")",
  "appcast_enclosure_url": "$(python3 -c 'import xml.etree.ElementTree as E,sys; print(E.parse(sys.argv[1]).getroot().find(".//enclosure").get("url"))' "$WORK/appcast.xml")",
  "appcast_signed": $(grep -q 'sparkle-signatures' "$WORK/appcast.xml" && echo true || echo false),
  "dmg_signature_verified": true,
  "feed_signature_verified": true,
  "public_key_source": "Resources/UpdateInfo.plist",
  "sparkle_framework_present": $([ -d "$FRAMEWORK" ] && echo true || echo false),
  "sparkle_xpc_removed": $([ -z "$(find "$FRAMEWORK" \( -name XPCServices -o -name '*.xpc' \) -print -quit)" ] && echo true || echo false),
  "sparkle_arch": "$(lipo -archs "$AUTOUPDATE")",
  "autoupdate_hardened_runtime": $(grep -qE '^CodeDirectory .*flags=.*\(.*runtime.*\)' <<<"$autoupdate_signature" && echo true || echo false),
  "autoupdate_entitlements_empty": $([ -z "$autoupdate_entitlements" ] && echo true || echo false),
  "cli_helper_links_sparkle": $(otool -L "$APP/Contents/MacOS/opentype-cli" | grep -q Sparkle && echo true || echo false)
}
JSON
