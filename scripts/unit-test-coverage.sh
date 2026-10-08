#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to parse Swift coverage JSON" >&2
  exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app"
fi

swift test --enable-code-coverage

CODECOV_PATH="$(swift test --show-codecov-path)"
THRESHOLD="${UNIT_COVERAGE_THRESHOLD:-80}"

UNIT_FILES_JSON='[
  "Sources/UtterContracts/Loc.swift",
  "Sources/UtterContracts/RemoteModelConfig.swift",
  "Sources/Prompts/PromptBuilder.swift",
  "Sources/Speech/GzipCompression.swift"
]'

PROJECT_TOTAL="$(
  jq -r --arg root "$ROOT_DIR/" '
    [.data[0].files[]
      | select(.filename | startswith($root + "Sources/"))
      | .summary.lines]
    | reduce .[] as $lines ({count: 0, covered: 0};
        .count += $lines.count | .covered += $lines.covered)
    | if .count == 0 then "0/0 100.00" else "\(.covered)/\(.count) \((.covered / .count * 10000 | round) / 100)" end
  ' "$CODECOV_PATH"
)"

UNIT_TOTAL="$(
  jq -r --arg root "$ROOT_DIR/" --argjson unitFiles "$UNIT_FILES_JSON" '
    [.data[0].files[]
      | .filename as $filename
      | ($filename | sub($root; "")) as $relative
      | select($unitFiles | index($relative))
      | .summary.lines]
    | reduce .[] as $lines ({count: 0, covered: 0};
        .count += $lines.count | .covered += $lines.covered)
    | if .count == 0 then "0/0 100.00" else "\(.covered)/\(.count) \((.covered / .count * 10000 | round) / 100)" end
  ' "$CODECOV_PATH"
)"

UNIT_PERCENT="$(awk '{print $2}' <<<"$UNIT_TOTAL")"

printf "Project source line coverage: %s%% (%s lines)\n" \
  "$(awk '{print $2}' <<<"$PROJECT_TOTAL")" \
  "$(awk '{print $1}' <<<"$PROJECT_TOTAL")"
printf "Unit core line coverage: %s%% (%s lines)\n" \
  "$UNIT_PERCENT" \
  "$(awk '{print $1}' <<<"$UNIT_TOTAL")"

awk -v actual="$UNIT_PERCENT" -v threshold="$THRESHOLD" '
  BEGIN {
    if (actual + 0 < threshold + 0) {
      printf("Unit core coverage %.2f%% is below %.2f%%\n", actual, threshold) > "/dev/stderr"
      exit 1
    }
  }
'
