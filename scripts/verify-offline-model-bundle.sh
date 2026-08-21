#!/usr/bin/env bash

set -euo pipefail

ROOT="${1:-}"
MODE="${2:-}"

if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    echo "error: offline model root is not a directory: $ROOT" >&2
    exit 1
fi
ROOT="$(cd "$ROOT" && pwd -P)"

has_content() {
    local path="$1"
    if [ -f "$path" ]; then
        [ -s "$path" ]
        return
    fi
    [ -d "$path" ] && find "$path" -type f -size +0c -print -quit | grep -q .
}

for file in config.json model.safetensors model.safetensors.index.json \
    preprocessor_config.json tokenizer_config.json vocab.json; do
    if [ ! -s "$ROOT/speech/$file" ]; then
        echo "error: incomplete Qwen3-ASR model: missing $file" >&2
        exit 1
    fi
done

RUNTIME_ROOT="$ROOT/speech-runtime"
RUNTIME_PYTHON="$RUNTIME_ROOT/bin/python"
RUNTIME_REQUIREMENT="qwen3-asr-mlx==0.1.1"
if [ ! -x "$RUNTIME_PYTHON" ]; then
    echo "error: incomplete Qwen3-ASR runtime: bin/python is not executable" >&2
    exit 1
fi
for marker in .opentype-runtime-ready .opentype-native-runtime-ready; do
    if [ ! -s "$RUNTIME_ROOT/$marker" ] \
        || [ "$(tr -d '\r\n' < "$RUNTIME_ROOT/$marker")" != "$RUNTIME_REQUIREMENT" ]; then
        echo "error: incomplete Qwen3-ASR runtime: invalid $marker" >&2
        exit 1
    fi
done

RUNTIME_PREFIX="$("$RUNTIME_PYTHON" -I -B -c \
    'import os, sys, qwen3_asr_mlx; print(os.path.realpath(sys.prefix)); print(os.path.realpath(sys.base_prefix))' \
    2>/dev/null)" || {
    echo "error: bundled Qwen3-ASR runtime cannot import qwen3_asr_mlx" >&2
    exit 1
}
while IFS= read -r prefix; do
    case "$prefix" in
        "$RUNTIME_ROOT"|"$RUNTIME_ROOT"/*) ;;
        *)
            echo "error: Qwen3-ASR runtime depends on Python outside speech-runtime: $prefix" >&2
            exit 1
            ;;
    esac
done <<EOF
$RUNTIME_PREFIX
EOF

if [ ! -s "$ROOT/formatting/config.json" ]; then
    echo "error: incomplete formatting model: missing config.json" >&2
    exit 1
fi

if [ ! -s "$ROOT/NOTICE" ] || ! has_content "$ROOT/LICENSES"; then
    echo "error: offline model bundle must include NOTICE and non-empty LICENSES" >&2
    exit 1
fi

if ! find "$ROOT/formatting" -type f \
    \( -name 'model.safetensors' -o -name 'weights.safetensors' -o -name '*.npz' \) \
    -size +0c -print -quit | grep -q . \
    && { [ ! -s "$ROOT/formatting/model.safetensors.index.json" ] \
        || ! find "$ROOT/formatting" -type f -name '*.safetensors' -size +0c -print -quit | grep -q .; }; then
    echo "error: incomplete formatting model: missing weights" >&2
    exit 1
fi

if [ "$MODE" != "--source" ]; then
    if [ ! -s "$ROOT/manifest.json" ] || [ ! -s "$ROOT/SHA256SUMS" ]; then
        echo "error: packaged offline bundle is missing its manifest or checksums" >&2
        exit 1
    fi
    (
        cd "$ROOT"
        shasum -a 256 -c SHA256SUMS >/dev/null
    )
fi

echo "Offline model bundle verified: $ROOT"
