#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/utter-industry-lexicon.XXXXXX")"
trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

swiftc -parse-as-library \
  "$ROOT_DIR/Sources/Processing/IndustryLexicon.swift" \
  "$ROOT_DIR/Sources/Processing/VocabularyReplacementEngine.swift" \
  "$ROOT_DIR/scripts/tests/industry_lexicon_deterministic.swift" \
  -o "$TEST_TEMP_DIR/industry-lexicon-tests"

"$TEST_TEMP_DIR/industry-lexicon-tests" \
  "$ROOT_DIR/Sources/Resources/IndustryLexicons.json"
