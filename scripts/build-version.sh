#!/usr/bin/env bash
# Resolve a numeric local bundle version without weakening public tag validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY="${1:-.}"
TAG="$(git -C "$REPOSITORY" describe --tags --abbrev=0 2>/dev/null || true)"

if [ -n "$TAG" ] && VERSION="$("$SCRIPT_DIR/release-version.sh" "$TAG" 2>/dev/null)"; then
    printf '%s\n' "$VERSION"
else
    printf '%s\n' "0.0.0"
fi
