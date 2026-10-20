#!/usr/bin/env bash
# Prove the independent CryptoKit verifier accepts only correctly signed inputs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
failures=0

check() {
    if ! "$@"; then
        echo "FAIL (expected success): $*" >&2
        failures=$((failures + 1))
    fi
}

rejects() {
    if "$@" > "$FIXTURE/rejected.log" 2>&1; then
        echo "FAIL (expected rejection): $*" >&2
        failures=$((failures + 1))
    fi
}

swift "$ROOT/scripts/tests/ed25519_fixture.swift" "$FIXTURE"
# Compile once: the run under test is the source file, not a copied implementation.
swiftc "$ROOT/scripts/verify-update-signature.swift" -o "$FIXTURE/verify"
VERIFY="$FIXTURE/verify"

PUBLIC="$(cat "$FIXTURE/public.txt")"
OTHER="$(cat "$FIXTURE/other-public.txt")"
SIGNATURE="$(cat "$FIXTURE/payload.sig")"

# DMG mode: valid, tampered, wrong key, short and malformed signatures, missing file.
check "$VERIFY" --public-key "$PUBLIC" --dmg "$FIXTURE/payload.bin" --signature "$SIGNATURE"
rejects "$VERIFY" --public-key "$PUBLIC" --dmg "$FIXTURE/payload-tampered.bin" --signature "$SIGNATURE"
rejects "$VERIFY" --public-key "$OTHER" --dmg "$FIXTURE/payload.bin" --signature "$SIGNATURE"
rejects "$VERIFY" --public-key "$PUBLIC" --dmg "$FIXTURE/payload.bin" --signature "$(cat "$FIXTURE/short-signature.txt")"
rejects "$VERIFY" --public-key "$PUBLIC" --dmg "$FIXTURE/payload.bin" --signature "$(cat "$FIXTURE/malformed-signature.txt")"
rejects "$VERIFY" --public-key "$PUBLIC" --dmg "$FIXTURE/missing.bin" --signature "$SIGNATURE"

# Feed mode: the trailing sparkle-signatures block drives the check.
check "$VERIFY" --public-key "$PUBLIC" --feed "$FIXTURE/feed.xml"
rejects "$VERIFY" --public-key "$OTHER" --feed "$FIXTURE/feed.xml"
rejects "$VERIFY" --public-key "$PUBLIC" --feed "$FIXTURE/feed-tampered.xml"
rejects "$VERIFY" --public-key "$PUBLIC" --feed "$FIXTURE/feed-unsigned.xml"
rejects "$VERIFY" --public-key "$PUBLIC" --feed "$FIXTURE/feed-bad-length.xml"
rejects "$VERIFY" --public-key "$PUBLIC" --feed "$FIXTURE/feed-bad-length-text.xml"

# Argument contract.
rejects "$VERIFY" --public-key "$PUBLIC"
rejects "$VERIFY" --public-key "$PUBLIC" --dmg "$FIXTURE/payload.bin" --feed "$FIXTURE/feed.xml"
rejects "$VERIFY" --public-key "$PUBLIC" --dmg "$FIXTURE/payload.bin" --signature "$SIGNATURE" --feed "$FIXTURE/feed.xml"
rejects "$VERIFY" --dmg "$FIXTURE/payload.bin" --signature "$SIGNATURE"
rejects "$VERIFY" --public-key "***" --dmg "$FIXTURE/payload.bin" --signature "$SIGNATURE"
rejects "$VERIFY" --public-key "$(printf 'AAAA')" --dmg "$FIXTURE/payload.bin" --signature "$SIGNATURE"

[ "$failures" -eq 0 ] || { echo "$failures update-signature checks failed." >&2; exit 1; }
echo "Update signature contract tests passed."
