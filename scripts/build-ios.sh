#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:---simulator}"
configuration="${2:-Debug}"
case "$configuration" in Debug|Release) ;; *) echo 'Configuration must be Debug or Release' >&2; exit 2 ;; esac
case "$mode" in
  --simulator) destination='generic/platform=iOS Simulator'; output=simulator; signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-) ;;
  --device) destination='generic/platform=iOS'; output=device; signing=(CODE_SIGNING_ALLOWED=NO) ;;
  *) echo 'Usage: bash scripts/build-ios.sh [--simulator|--device] [Debug|Release]' >&2; exit 2 ;;
esac
cd "$ROOT_DIR"
resolved_dir=iOS/Utter.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$resolved_dir"
cp Package.resolved "$resolved_dir/Package.resolved"
xcodebuild -project iOS/Utter.xcodeproj -scheme UtteriOS -configuration "$configuration" \
  -destination "$destination" -derivedDataPath ".build-ios/$output" \
  -clonedSourcePackagesDirPath .build-ios/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates "${signing[@]}" build
