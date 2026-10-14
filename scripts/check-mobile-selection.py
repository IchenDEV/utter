#!/usr/bin/env python3
"""Exercise actual mobile selection methods, shared control/recipe and bridge with explicit native/model seams."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--bridge-build", type=Path, required=True)
parser.add_argument("--core-build-manifest", type=Path, required=True)
parser.add_argument("--lifecycle", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = args.output.resolve()
out.mkdir(exist_ok=False, parents=True)
assert shutil.disk_usage(root).free >= 10 * 1024**3
bridge = args.bridge_build.resolve()
check = json.loads((bridge / "check.json").read_text())
assert check.get("step2ExitCode") == 0
for path, digest in check["sourceSHA256"].items():
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest, path
core = json.loads(args.core_build_manifest.read_text())
assert core["exitCode"] == 0 and core["sourceUnchanged"]
for path, digest in core["sourceSHA256"].items():
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest, path
for path, digest in core["objectSHA256"].items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, path
fixture = root / ("scripts/fixtures/mobile-selection-lifecycle.swift" if args.lifecycle else "scripts/fixtures/mobile-selection.swift")
mobile = root / "Sources/UtterMobile/MobileSelection.swift"
writer = root / "iOS/Keyboard/KeyboardSelectionOutput.swift"
controller = root / "iOS/Keyboard/KeyboardController+Selection.swift"
source = controller.read_text()
start = source.index("    func observeOwnedSelectionChange(")
end = source.index("    func expireSelectionRestoration()", start)
def portable(path):
    return path.read_text().replace("#if os(iOS)\n", "").rsplit("#endif", 1)[0]

def method(path, first):
    source = path.read_text()
    start = source.index(first)
    # Extract this four-space-indented method, without depending on the next member's name.
    end = source.index("\n    }\n", start) + len("\n    }\n")
    return source[start:end]

inputs = [fixture, mobile, writer, controller]
harness = fixture.read_text() + "\n" + portable(mobile)
harness += "\n" + writer.read_text().replace("import UIKit\n", "")
if args.lifecycle:
    base = root / "scripts/fixtures/mobile-selection.swift"
    app = root / "Sources/UtterMobile/MobileController.swift"
    selection = root / "Sources/UtterMobile/MobileController+Selection.swift"
    capture = root / "Sources/UtterMobile/MobileController+KeyboardCapture.swift"
    keyboard = root / "iOS/Keyboard/KeyboardController.swift"
    standby = root / "iOS/App/StandbyService.swift"
    inputs += [base, app, selection, capture, keyboard, standby]
    harness += "\n" + base.read_text().split("@MainActor final class MobileJob")[0]
    harness += "\n" + source.replace("import UIKit\n", "")
    harness += "\n" + portable(selection)
    harness += "\nextension MobileController {\n"
    harness += method(app, "    public func stop()")
    harness += method(app, "    public func cancel()")
    harness += method(app, "    public func perform(")
    harness += method(capture, "    func watchLease(") + "}\n"
    harness += "\nextension KeyboardController {\n"
    for first in ["    func currentSignature()", "    func refresh()", "    func waitForInvalidatedSession()",
                  "    func invalidate()", "    func prepare("]:
        harness += method(keyboard, first)
    harness += "}\n\nextension StandbyService {\n"
    harness += method(standby, "    private func serve(") + "}\n"
else:
    harness += "\nextension KeyboardController {\n" + source[start:end] + "}\n"
(out / "check.swift").write_text(harness)
products = root / ".build/out/Products/Debug"
resources = products / "OpenType_UtterContracts.bundle"
assert resources.is_dir(), "Existing localization resource bundle required"
objects = [Path(p) for p in core["objectSHA256"]]
assert all(path.is_file() for path in objects), "Existing current core build required"
env = {**os.environ, "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
       "PACKAGE_RESOURCE_BUNDLE_PATH": str(products)}
def xcrun(*flags):
    return subprocess.check_output(["xcrun", *flags], env=env, text=True).strip()

command = [xcrun("--find", "swiftc"), "-swift-version", "5", "-package-name", root.name.replace("-", "_"), "-sdk",
           xcrun("--sdk", "macosx", "--show-sdk-path"), "-target", "arm64-apple-macosx26.0", "-parse-as-library",
           "-I", str(products), "-I", str(bridge), "-L", str(bridge), "-lUtterKeyboardBridge",
           "-Xlinker", "-rpath", "-Xlinker", str(bridge), str(out / "check.swift"), *map(str, objects), "-o", str(out / "check")]
report = {"startedAt": datetime.now().astimezone().isoformat(), "command": command,
          "scope": "Actual mobile selection, controller command/Stop/projection, keyboard polling/Apply/Restore and standby serial loop with real shared SessionDriver/recipe and bridge I/O when --lifecycle; otherwise selection methods/control only. Capture/ASR, platform controller setup, UIKit proxy and raw model generation are controlled seams. No microphone/model/device/UI execution.",
          "sources": {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
          "objects": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in objects},
          "resourceSHA256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(resources.rglob("*")) if p.is_file()},
          "resourceOverride": env["PACKAGE_RESOURCE_BUNDLE_PATH"],
          "bridgeCheck": str(bridge / "check.json"), "coreBuildManifest": str(args.core_build_manifest.resolve()), "deviceActions": 0}
compiled = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
(out / "compile.log").write_text(compiled.stdout + compiled.stderr)
report["compileExitCode"] = code = compiled.returncode
if code == 0:
    result = subprocess.run([str(out / "check")], env=env, capture_output=True, text=True, timeout=45)
    (out / "result.json").write_text(result.stdout)
    (out / "stderr.log").write_text(result.stderr)
    report["checkExitCode"] = code = result.returncode
    if code == 0: report["result"] = json.loads(result.stdout)
report["endedAt"] = datetime.now().astimezone().isoformat()
report["sourceUnchanged"] = all(hashlib.sha256((root / path).read_bytes()).hexdigest() == digest for path, digest in report["sources"].items())
report["objectsUnchanged"] = all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in report["objects"].items())
if not report["sourceUnchanged"] or not report["objectsUnchanged"]:
    code = 2
(out / "check.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({k: v for k, v in report.items() if k not in ["command", "objects", "sources", "resourceSHA256"]}, indent=2))
raise SystemExit(code)
