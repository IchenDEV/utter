#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$SCRIPT_DIR/build-version.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -r "$FIXTURE"' EXIT

git -C "$FIXTURE" init -q
[ "$($VALIDATOR "$FIXTURE")" = "0.0.0" ]

git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -qm base
git -C "$FIXTURE" tag v1.2.3
[ "$($VALIDATOR "$FIXTURE")" = "1.2.3" ]

git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -qm prerelease
git -C "$FIXTURE" tag v1.2.3-beta
[ "$($VALIDATOR "$FIXTURE")" = "0.0.0" ]

echo "Build version tests passed."
