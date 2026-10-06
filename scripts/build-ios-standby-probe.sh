#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
probe_dir="$ROOT_DIR/.build-ios/standby-probe"
device_id=""
if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == "--device" && -n "$2" ]] || { echo "Usage: $0 [--device UDID]" >&2; exit 2; }
  device_id="$2"
  : "${UTTER_DEVELOPMENT_TEAM:?Set UTTER_DEVELOPMENT_TEAM for device builds}"
  probe_dir="$ROOT_DIR/.build-ios/standby-device-probe"
fi
mkdir -p "$probe_dir"
python3 - "$ROOT_DIR" "$probe_dir" <<'PY'
from pathlib import Path
import shutil, sys, plistlib, json, subprocess
root, out = map(Path, sys.argv[1:])
project = out / "iOS"
shutil.copytree(root / "iOS", project, dirs_exist_ok=True)
for filename, destination in [("StandbyProbe.swift", "App/UtterPhoneApp.swift"),
                              ("StandbyFlow.swift", "UITests/UtterSimulatorFlow.swift")]:
    shutil.copy(root / "scripts/tests/ios-standby" / filename, project / destination)
for name in ["UtterSimulatorSettings", "UtterDeviceChecks", "UtterDeviceSpeech", "UtterDeviceStandby"]:
    (project / f"UITests/{name}.swift").write_text("import XCTest\n")
shutil.copy(root / "scripts/tests/ios-standby/StandbySafariFlow.swift", project / "UITests/UtterDeviceChecks.swift")
for name in ["DictionaryView", "MobileModelsView", "MobileSettingsView"]:
    (project / f"App/{name}.swift").write_text("import SwiftUI\n")
pbx = project / "Utter.xcodeproj/project.pbxproj"
text = pbx.read_text().replace("relativePath = ..;", f'relativePath = "{root}";')
text = text.replace("../Sources/", str(root / "Sources") + "/")
pbx.write_text(text)
host = out / "StandbyHost.app"
host.mkdir(exist_ok=True)
with (host / "Info.plist").open("wb") as f:
    plistlib.dump({"CFBundleIdentifier": "com.ichendev.utter.standbyhost",
                  "CFBundleExecutable": "StandbyHost", "CFBundleName": "StandbyHost",
                  "CFBundleDisplayName": "Standby Host", "CFBundlePackageType": "APPL",
                  "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1",
                  "LSRequiresIPhoneOS": True, "MinimumOSVersion": "27.0",
                  "UIBackgroundModes": ["audio"], "UILaunchScreen": {},
                  "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"]}, f)
with (out / "Host.entitlements").open("wb") as f:
    plistlib.dump({"com.apple.security.application-groups": ["group.com.ichendev.utter.ios"]}, f)
# Reuse the project format for a native, separately signed physical video host.
host_project = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(pbx)]))
objects = host_project["objects"]
target_id = next(key for key, value in objects.items() if value.get("isa") == "PBXNativeTarget" and value.get("name") == "Utter")
shutil.copy(root / "scripts/tests/ios-standby/StandbyFrame.swift", project / "App/StandbyFrame.swift")
objects["STANDBY_FRAME_REF"] = dict(isa="PBXFileReference", lastKnownFileType="sourcecode.swift", path="App/StandbyFrame.swift", sourceTree="<group>")
objects["STANDBY_FRAME_BUILD"] = dict(isa="PBXBuildFile", fileRef="STANDBY_FRAME_REF")
for phase_id in objects[target_id]["buildPhases"]:
    if objects[phase_id]["isa"] == "PBXSourcesBuildPhase": objects[phase_id]["files"].append("STANDBY_FRAME_BUILD")
pbx.write_bytes(plistlib.dumps(host_project))
target = objects[target_id]
target.update(name="StandbyHost", productName="StandbyHost", dependencies=[], packageProductDependencies=[])
objects[target["productReference"]]["path"] = "StandbyHost.app"
main_project = objects[host_project["rootObject"]]
main_project.update(targets=[target_id], packageReferences=[])
objects["STANDBY_VIDEO_REF"] = dict(isa="PBXFileReference", lastKnownFileType="file", path=str(host / "probe.mp4"), sourceTree="<absolute>")
objects["STANDBY_VIDEO_BUILD"] = dict(isa="PBXBuildFile", fileRef="STANDBY_VIDEO_REF")
phases = []
for phase_id in target["buildPhases"]:
    phase = objects[phase_id]
    if phase["isa"] == "PBXSourcesBuildPhase":
        source_id = next(key for key in phase["files"] if objects[objects[key]["fileRef"]].get("path") == "App/UtterPhoneApp.swift")
        objects[objects[source_id]["fileRef"]].update(path=str(root / "scripts/tests/ios-standby/StandbyHost.swift"), sourceTree="<absolute>")
        phase["files"] = [source_id]
    elif phase["isa"] == "PBXResourcesBuildPhase": phase["files"] = ["STANDBY_VIDEO_BUILD"]
    elif phase["isa"] == "PBXFrameworksBuildPhase": phase["files"] = []
    else: continue
    phases.append(phase_id)
target["buildPhases"] = phases
for config_id in objects[target["buildConfigurationList"]]["buildConfigurations"]:
    config = objects[config_id]
    config.pop("baseConfigurationReference", None)
    config["buildSettings"] = dict(PRODUCT_NAME="StandbyHost", PRODUCT_BUNDLE_IDENTIFIER="com.ichendev.utter.standbyhost",
        INFOPLIST_FILE=str(host / "Info.plist"),
        CODE_SIGN_STYLE="Automatic", SDKROOT="iphoneos", IPHONEOS_DEPLOYMENT_TARGET="27.0",
        TARGETED_DEVICE_FAMILY="1,2", SWIFT_VERSION="5.0", GENERATE_INFOPLIST_FILE="NO")
host_project_dir = out / "StandbyHost.xcodeproj"
host_project_dir.mkdir(exist_ok=True)
(host_project_dir / "project.pbxproj").write_bytes(plistlib.dumps(host_project))
PY
cp Package.resolved "$probe_dir/iOS/Utter.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if [[ ! -f "$probe_dir/StandbyHost.app/probe.mp4" ]]; then
  ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=160x90:rate=5 \
    -t 600 -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$probe_dir/StandbyHost.app/probe.mp4"
fi
if [[ -n "$device_id" ]]; then
  xcodebuild -project "$probe_dir/StandbyHost.xcodeproj" -target StandbyHost -configuration Debug \
    -sdk iphoneos CONFIGURATION_BUILD_DIR="$probe_dir/host-build" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$UTTER_DEVELOPMENT_TEAM" CODE_SIGN_IDENTITY='Apple Development' build
  xcodebuild -project "$probe_dir/iOS/Utter.xcodeproj" -scheme UtteriOS -configuration Debug \
    -destination "id=$device_id" -derivedDataPath "$probe_dir/build" \
    -clonedSourcePackagesDirPath "$ROOT_DIR/.build-ios/SourcePackages" \
    -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$UTTER_DEVELOPMENT_TEAM" TARGETED_DEVICE_FAMILY=1,2 \
    CODE_SIGN_IDENTITY='Apple Development' build-for-testing
  exit
fi
xcrun --sdk iphonesimulator swiftc -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios27.0-simulator -parse-as-library scripts/tests/ios-standby/StandbyHost.swift \
  -o "$probe_dir/StandbyHost.app/StandbyHost"
codesign --force --sign - --entitlements "$probe_dir/Host.entitlements" "$probe_dir/StandbyHost.app"
xcodebuild -project "$probe_dir/iOS/Utter.xcodeproj" -scheme UtteriOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$probe_dir/build" \
  -clonedSourcePackagesDirPath "$ROOT_DIR/.build-ios/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build-for-testing
