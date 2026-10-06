#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .build-ios/checks
swiftc -parse-as-library -swift-version 5 Sources/UtterKeyboardBridge/*.swift \
  scripts/tests/ios-bridge-scenario.swift -o .build-ios/checks/ios-bridge-scenario
.build-ios/checks/ios-bridge-scenario
