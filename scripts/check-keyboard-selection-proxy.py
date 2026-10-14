#!/usr/bin/env python3
"""Check actual native writer with a stub proxy and the already-verified bridge module."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--bridge-build", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
folder = args.output.resolve()
folder.mkdir(parents=True, exist_ok=False)
bridge = args.bridge_build.resolve()
manifest = json.loads((bridge / "check.json").read_text())
assert manifest.get("step2ExitCode") == 0, "Actual bridge XCTest must pass first"
for name, expected in manifest["sourceSHA256"].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, "Bridge source changed after its checks"
source = root / "iOS/Keyboard/KeyboardSelectionOutput.swift"
fixture = root / "scripts/fixtures/keyboard-selection-proxy.swift"
harness = fixture.read_text() + "\n" + source.read_text().replace("import UIKit\n", "")
(folder / "proxy-check.swift").write_text(harness)
environment = {**os.environ, "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}
def xcrun(*arguments):
    return subprocess.check_output(["xcrun", *arguments], env=environment, text=True).strip()

command = [xcrun("--find", "swiftc"), "-swift-version", "5", "-sdk", xcrun("--sdk", "macosx", "--show-sdk-path"),
           "-target", "arm64-apple-macosx26.0", "-module-cache-path", str(root / ".build-ios/ipad-device/ModuleCache.noindex"),
           "-I", str(bridge), "-L", str(bridge), "-lUtterKeyboardBridge", "-Xlinker", "-rpath", "-Xlinker", str(bridge),
           "-parse-as-library", str(folder / "proxy-check.swift"), "-o", str(folder / "proxy-check")]
report = {"startedAt": datetime.now().astimezone().isoformat(), "compileCommand": command,
          "sourceSHA256": {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source, fixture]},
          "bridgeCheck": str(bridge / "check.json"), "deviceCommandsExecuted": False}
compiled = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=60)
(folder / "compile.log").write_text(compiled.stdout + compiled.stderr)
report["compileExitCode"] = code = compiled.returncode
if code == 0:
    checked = subprocess.run([str(folder / "proxy-check")], capture_output=True, text=True, timeout=10)
    (folder / "result.json").write_text(checked.stdout)
    (folder / "stderr.log").write_text(checked.stderr)
    report["checkExitCode"] = code = checked.returncode
    if code == 0: report["result"] = json.loads(checked.stdout)
report["endedAt"] = datetime.now().astimezone().isoformat()
(folder / "check.json").write_text(json.dumps(report, indent=2))
print(json.dumps({k: v for k, v in report.items() if k not in ["compileCommand", "sourceSHA256"]}, indent=2))
raise SystemExit(code)
