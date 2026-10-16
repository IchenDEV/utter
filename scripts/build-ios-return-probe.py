#!/usr/bin/env python3
"""Build one real mobile return probe; restore formal plist and preserve evidence."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import plistlib
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path, help="New evidence directory")
parser.add_argument("--packages", type=Path, required=True, help="Existing Xcode SourcePackages cache")
parser.add_argument("--compile-only", action="store_true", help="Unsigned compiler candidate, never installed")
parser.add_argument("--formal-plist", action="store_true", help="Keep the formal Plist without the scene-return experiment")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
folder = args.output.resolve()
folder.mkdir(parents=True, exist_ok=False)
assert shutil.disk_usage(root).free >= 10 * 1024**3, "Data below 10 GiB build floor"
packages = args.packages.resolve()
assert (packages / "workspace-state.json").is_file(), "Existing dependency cache required"
plist = root / "iOS/Configuration/App-Info.plist"
original = plist.read_bytes()
(folder / "formal-App-Info.plist").write_bytes(original)
info = plistlib.loads(original)
if not args.formal_plist: info["UIApplicationSceneManifest"] = {"UIApplicationSupportsMultipleScenes": True}
temporary = original if args.formal_plist else plistlib.dumps(info)
environment = {**os.environ, "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}
command = ["/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", "-project", "iOS/Utter.xcodeproj",
           "-scheme", "UtteriOS", "-configuration", "Debug", "-destination", "generic/platform=iOS",
           "-derivedDataPath", ".build-ios/ipad-device", "-clonedSourcePackagesDirPath", str(packages),
           "-onlyUsePackageVersionsFromResolvedFile", "-skipPackageUpdates", "-jobs", "2",
           "CODE_SIGNING_ALLOWED=" + ("NO" if args.compile_only else "YES"), "build-for-testing"]
report = {"startedAt": datetime.now().astimezone().isoformat(), "command": command,
          "compileOnly": args.compile_only, "formalPlist": args.formal_plist, "deviceCommandsExecuted": False,
          "formalPlistSHA256": hashlib.sha256(original).hexdigest(),
          "probePlistSHA256": hashlib.sha256(temporary).hexdigest(), "minimumFreeBytes": 10 * 1024**3}
process = None
def snapshot(name, artifacts=()):
    capture = ["python3", "scripts/capture-candidate.py", str(folder / name)]
    for artifact in artifacts: capture.extend(["--artifact", str(artifact)])
    subprocess.run(capture, cwd=root, check=True, stdout=subprocess.DEVNULL)

try:
    plist.write_bytes(temporary)
    snapshot("prebuild.json")
    with (folder / "build.log").open("w") as log:
        process = subprocess.Popen(command, cwd=root, env=environment, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        report["pid"] = process.pid
        (folder / "running.json").write_text(json.dumps(report, indent=2))
        print(json.dumps({"pid": process.pid, "log": str(folder / "build.log"), "compileOnly": args.compile_only}), flush=True)
        while process.poll() is None:
            free = shutil.disk_usage(root).free
            if free < report["minimumFreeBytes"]:
                report["capacityBlocked"] = True
                os.killpg(process.pid, signal.SIGTERM)
                break
            time.sleep(5)
        report["exitCode"] = process.wait()
    app = root / ".build-ios/ipad-device/Build/Products/Debug-iphoneos/Utter.app"
    artifacts = [app / "Utter", app / "PlugIns/UtterKeyboard.appex/UtterKeyboard",
                 app / "PlugIns/UtterLiveActivity.appex/UtterLiveActivity"] if report["exitCode"] == 0 else []
    snapshot("postbuild.json", artifacts)
finally:
    if process is not None and process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait()
    if plist.read_bytes() == temporary:
        plist.write_bytes(original)
        report["formalPlistRestored"] = True
    else:
        report["formalPlistRestored"] = False
        report["restoreConflict"] = "Plist changed by another writer; not overwritten"
    report["endedAt"] = datetime.now().astimezone().isoformat()
    report["freeBytes"] = shutil.disk_usage(root).free
    (folder / "result.json").write_text(json.dumps(report, indent=2))
    snapshot("formal-source-after.json")
    print(json.dumps(report, indent=2), flush=True)
raise SystemExit(report.get("exitCode", 1) if report["formalPlistRestored"] else 1)
