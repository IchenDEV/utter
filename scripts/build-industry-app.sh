#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_ROOT=""
BUILD_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --model-root=*) MODEL_ROOT="${arg#*=}" ;;
        --help|-h)
            echo "Usage: $0 --model-root=PATH [--version=X.Y.Z] [--app-only] [--sign=IDENTITY]"
            echo ""
            echo "PATH must contain speech/, speech-runtime/, formatting/, LICENSES/, and NOTICE."
            exit 0
            ;;
        *) BUILD_ARGS+=("$arg") ;;
    esac
done

if [ -z "$MODEL_ROOT" ]; then
    echo "error: --model-root=PATH is required for the medical offline edition" >&2
    exit 1
fi

exec "${SCRIPT_DIR}/build-app.sh" \
    --offline-model-root="$MODEL_ROOT" \
    "${BUILD_ARGS[@]}"
