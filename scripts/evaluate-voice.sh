#!/usr/bin/env bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if [[ "$(uname -s)" != Darwin ]]; then
    echo "Voice model evaluation requires macOS 26 on Apple Silicon." >&2
    exit 1
fi

eval_derived="$task_root/.build/voice-evaluation"
xcodebuild -scheme UtterVoiceEval -configuration Release -derivedDataPath "$eval_derived" \
    -destination 'platform=macOS,arch=arm64' build
export UTTER_EVAL_REVISION="$(git rev-parse HEAD)"
exec "$eval_derived/Build/Products/Release/UtterVoiceEval" "$@"
