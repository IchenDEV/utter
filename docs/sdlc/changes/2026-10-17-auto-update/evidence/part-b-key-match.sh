#!/usr/bin/env bash
#
# Key-ceremony evidence: prove the committed public key is the one shipped in
# Resources/UpdateInfo.plist and the one whose private half signs releases.
#
# The private key is never exported or printed: Sparkle's sign_update reads it
# from the login keychain and prints only a signature, which is then checked by
# the same CryptoKit verifier the release pipeline runs.
#
# usage: part-b-key-match.sh [SPARKLE_TOOLS_BIN]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
TOOLS="${1:-$ROOT/.build/artifacts/sparkle/Sparkle/bin}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -x "$TOOLS/sign_update" ] || { echo "no sign_update in $TOOLS" >&2; exit 1; }

PUBLIC="$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["SUPublicEDKey"])' \
    "$ROOT/Resources/UpdateInfo.plist")"
KEYCHAIN_PUBLIC="$("$TOOLS/generate_keys" -p)"

head -c 4096 /dev/urandom > "$WORK/fixture.dmg"
SIGNATURE="$("$TOOLS/sign_update" -p "$WORK/fixture.dmg")"
"$ROOT/scripts/verify-update-signature.swift" --public-key "$PUBLIC" \
    --dmg "$WORK/fixture.dmg" --signature "$SIGNATURE" > "$WORK/verified.log"

wrong_rejected=false
if "$ROOT/scripts/verify-update-signature.swift" --public-key "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" \
        --dmg "$WORK/fixture.dmg" --signature "$SIGNATURE" > "$WORK/wrong.log" 2>&1; then
    echo "a wrong public key verified" >&2
    exit 1
fi
wrong_rejected=true

cat <<JSON
{
  "committed_public_key_source": "Resources/UpdateInfo.plist",
  "committed_public_key_matches_keychain": $([ "$PUBLIC" = "$KEYCHAIN_PUBLIC" ] && echo true || echo false),
  "keychain_public_key": "$KEYCHAIN_PUBLIC",
  "signed_with_keychain_key_verifies_against_committed_key": true,
  "wrong_public_key_rejected": $wrong_rejected,
  "private_key_exported": false
}
JSON
