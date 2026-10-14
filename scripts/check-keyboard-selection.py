#!/usr/bin/env python3
"""Run real bridge XCTest cases directly, without fetching the app's model dependencies."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path, help="New evidence directory")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
folder = args.output.resolve()
folder.mkdir(parents=True, exist_ok=False)
sources = sorted((root / "Sources/UtterKeyboardBridge").glob("*.swift"))
tests = sorted((root / "Tests/UtterKeyboardBridgeTests").glob("*.swift"))
count = sum(len(re.findall(r"^\s+func (test\w+)\(\)", p.read_text(), re.MULTILINE)) for p in tests)
bundle = folder / "KeyboardTests.xctest"
(bundle / "Contents/MacOS").mkdir(parents=True)
(bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "KeyboardTests",
    "CFBundleIdentifier": "com.ichendev.utter.keyboard-local-tests", "CFBundlePackageType": "BNDL"}))
environment = {**os.environ, "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}
def xcrun(*arguments):
    return subprocess.check_output(["xcrun", *arguments], env=environment, text=True).strip()

compiler = xcrun("--find", "swiftc")
frameworks = Path(environment["DEVELOPER_DIR"]) / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
support = frameworks.parents[1] / "usr/lib"
assert support.is_dir(), "XCTest Swift support must be present"
flags = ["-swift-version", "5", "-sdk", xcrun("--sdk", "macosx", "--show-sdk-path"), "-target",
         "arm64-apple-macosx26.0", "-module-cache-path", str(root / ".build-ios/ipad-device/ModuleCache.noindex")]
commands = [
    [compiler, *flags, "-emit-library", "-emit-module", "-enable-testing", "-module-name", "UtterKeyboardBridge",
     *map(str, sources), "-emit-module-path", str(folder / "UtterKeyboardBridge.swiftmodule"),
     "-o", str(folder / "libUtterKeyboardBridge.dylib")],
    [compiler, *flags, "-emit-library", "-module-name", "KeyboardTests", "-I", str(folder), "-I", str(support),
     "-L", str(folder), "-lUtterKeyboardBridge", "-L", str(support), "-lXCTestSwiftSupport", "-F", str(frameworks),
     "-Xlinker", "-rpath", "-Xlinker", str(folder), "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
     "-Xlinker", "-rpath", "-Xlinker", str(support), *map(str, tests), "-o", str(bundle / "Contents/MacOS/KeyboardTests")],
    [xcrun("--find", "xctest"), str(bundle)]
]
report = {"startedAt": datetime.now().astimezone().isoformat(), "scope": "Actual portable bridge module and XCTest tests; no UIKit/recording/model execution",
          "deviceCommandsExecuted": False, "commands": commands, "testCount": count,
          "sourceSHA256": {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources, *tests]}}
code = 0
for index, command in enumerate(commands):
    result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=60)
    (folder / f"step-{index}.log").write_text(result.stdout + result.stderr)
    report[f"step{index}ExitCode"] = code = result.returncode
    if code != 0: break
report["endedAt"] = datetime.now().astimezone().isoformat()
(folder / "check.json").write_text(json.dumps(report, indent=2))
print(json.dumps({k: v for k, v in report.items() if k not in ["commands", "sourceSHA256"]}, indent=2))
raise SystemExit(code)
