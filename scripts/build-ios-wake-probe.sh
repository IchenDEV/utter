#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
probe_dir="$ROOT_DIR/.build-ios/wake-probe"
mkdir -p "$probe_dir"
python3 - "$ROOT_DIR" "$probe_dir" <<'PY'
from pathlib import Path
import hashlib, json, plistlib, shutil, sys
root, out = map(Path, sys.argv[1:])
project = out / "iOS"
shutil.copytree(root / "iOS", project, dirs_exist_ok=True)
overlays = {"WakeProbe.swift": "App/UtterPhoneApp.swift",
            "WakeKeyboard.swift": "Keyboard/KeyboardView.swift",
            "WakeFlow.swift": "UITests/UtterSimulatorFlow.swift"}
(out / "original-source-hashes.json").write_text(json.dumps({str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in (root / "iOS").rglob("*") if p.is_file()}, indent=2))
for filename, destination in overlays.items():
    shutil.copy(root / "scripts/tests/ios-wake" / filename, project / destination)
(project / "UITests/UtterSimulatorSettings.swift").write_text("import XCTest\n")
pbx = project / "Utter.xcodeproj/project.pbxproj"
pbx.write_text(pbx.read_text().replace("relativePath = ..;", f'relativePath = "{root}";')
               .replace("../Sources/", str(root / "Sources") + "/"))
info = project / "Configuration/App-Info.plist"
with info.open("rb") as f: values = plistlib.load(f)
values["CFBundleURLTypes"] = [{"CFBundleURLSchemes": ["utter-wake-probe"], "CFBundleURLName": "Wake experiment"}]
values.pop("UIBackgroundModes", None)
with info.open("wb") as f: plistlib.dump(values, f)
host = out / "WakeHost.app"
host.mkdir(exist_ok=True)
with (host / "Info.plist").open("wb") as f:
    plistlib.dump({"CFBundleIdentifier": "com.ichendev.utter.wakehost", "CFBundleExecutable": "WakeHost",
                  "CFBundleName": "WakeHost", "CFBundleDisplayName": "Wake Host", "CFBundlePackageType": "APPL",
                  "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1", "LSRequiresIPhoneOS": True,
                  "MinimumOSVersion": "27.0", "UILaunchScreen": {},
                  "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"]}, f)
PY
xcrun --sdk iphonesimulator swiftc -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios27.0-simulator -parse-as-library scripts/tests/ios-wake/WakeHost.swift \
  -o "$probe_dir/WakeHost.app/WakeHost"
codesign --force --sign - "$probe_dir/WakeHost.app"
cp Package.resolved "$probe_dir/iOS/Utter.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
xcodebuild -project "$probe_dir/iOS/Utter.xcodeproj" -scheme UtteriOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$probe_dir/build" \
  -clonedSourcePackagesDirPath "$ROOT_DIR/.build-ios/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build-for-testing
