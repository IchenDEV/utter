#!/usr/bin/env bash
# Validate a stable public release tag and print its numeric bundle version.

set -euo pipefail

TAG="${1:-}"
if [[ ! "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "error: release tag must be stable vMAJOR.MINOR.PATCH without leading zeroes" >&2
    exit 1
fi

printf '%s\n' "${TAG#v}"
