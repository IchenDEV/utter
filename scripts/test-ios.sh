#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
simulator_id="${1:?Usage: bash scripts/test-ios.sh SIMULATOR_UUID}"
cd "$ROOT_DIR"
resolved_dir=iOS/Utter.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$resolved_dir"
cp Package.resolved "$resolved_dir/Package.resolved"
xcodebuild -project iOS/Utter.xcodeproj -scheme UtteriOS -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" -derivedDataPath .build-ios/simulator \
  -clonedSourcePackagesDirPath .build-ios/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- "${@:2}" test
