#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$SCRIPT_DIR/release-version.sh"
REPOSITORY="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$REPOSITORY/.github/workflows/release.yml"

for tag in v0.0.0 v1.2.3 v10.20.300; do
    expected="${tag#v}"
    actual="$($VALIDATOR "$tag")"
    [ "$actual" = "$expected" ] || exit 1
done

for tag in 1.2.3 v01.2.3 v1.02.3 v1.2.03 v1.2 v1.2.3-beta v1.2.3+build; do
    if "$VALIDATOR" "$tag" >/dev/null 2>&1; then
        echo "error: invalid release tag accepted: $tag" >&2
        exit 1
    fi
done

grep -Fq 'SIGNING_MODE=self-signed' "$WORKFLOW"
[ "$(grep -Fc 'VERIFY_ARGS+=(--require-self-signed)' "$WORKFLOW")" -eq 2 ]
grep -Fq 'VERIFY_ARGS+=(--require-developer-id --require-notarization)' "$WORKFLOW"
[ "$(grep -Fc -- '--expected-cert-sha256 "$SIGN_CERT_SHA256"' "$WORKFLOW")" -eq 2 ]
grep -Fq "if: env.SIGNING_MODE == 'developer-id'" "$WORKFLOW"
grep -Fq 'This release is signed with the project self-signed certificate' "$WORKFLOW"
if grep -Eq -- '--clobber|--sign=-|will use ad-hoc' "$WORKFLOW"; then
    echo "error: release workflow can replace assets or fall back to ad-hoc signing" >&2
    exit 1
fi

echo "Release version tests passed."
