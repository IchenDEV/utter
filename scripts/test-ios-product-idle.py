#!/usr/bin/env python3
"""Debugger-free check that the product app keeps serving in the background while its standby PiP is active.

Usage: test-ios-product-idle.py [SECONDS] [--keep] [--control]
Launches the Debug product with --standby-autostart through devicectl, activates Safari, then samples the
app's own heartbeat journal. A heartbeat older than the keyboard's 20 second timeout means standby is dead.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
output = root / ".build-ios/product-idle"
output.mkdir(parents=True, exist_ok=True)
device = "00008130-00092D800891401C"
bundle = "com.ichendev.utter.ios"
app = root / ".build-ios/ipad-device/Build/Products/Debug-iphoneos/Utter.app"
environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
arguments = [argument for argument in sys.argv[1:] if not argument.startswith("--")]
duration = int(arguments[0]) if arguments else 90
keep = "--keep" in sys.argv
control = "--control" in sys.argv  # same loop without PiP; expected to be suspended
timeout = 20  # BridgeStatus.heartbeatTimeout


def devicectl(name, *parts):
    result = subprocess.run(["xcrun", "devicectl", "--timeout", "30", *parts], cwd=root, env=environment,
                            text=True, capture_output=True, timeout=45)
    (output / f"{name}.log").write_text(result.stdout + result.stderr)
    result.check_returncode()


def heartbeat(name):
    destination = output / f"{name}.json"
    devicectl(name, "device", "copy", "from", "--device", device, "--domain-type", "appDataContainer",
              "--domain-identifier", bundle, "--source", "Library/standby-heartbeat.json", "--destination", str(destination))
    return json.loads(destination.read_text())


def sample(name):
    try:
        row = heartbeat(name)
    except subprocess.CalledProcessError:
        return None
    row["age"] = time.time() - row["time"]
    return row


devicectl("install", "device", "install", "app", "--device", device, str(app))
devicectl("launch", "device", "process", "launch", "--device", device, "--terminate-existing",
          "--json-output", str(output / "launch.json"), bundle, "--standby-autostart", *(["--standby-control"] if control else []))
pid = json.loads((output / "launch.json").read_text())["result"]["process"]["processIdentifier"]
initial = None
for attempt in range(30):
    time.sleep(1)
    initial = sample("initial")
    if initial and initial["pid"] == pid and (control or initial["pipActive"]) and initial["age"] < 8:
        break
else:
    sys.exit(f"Standby never became active in the foreground: {initial}")
print(f"PID {pid}: PiP active in foreground; activating Safari without XCTest/debugger", flush=True)

devicectl("safari", "device", "process", "launch", "--device", device, "com.apple.mobilesafari")
started = time.monotonic()
rows = []
failed = False
try:
    for elapsed in range(15, duration + 1, 15):
        time.sleep(max(0, started + elapsed - time.monotonic()))
        row = sample(f"background-{elapsed}")
        rows.append(dict(elapsed=elapsed, **(row or {"missing": True})))
        alive = bool(row) and row["pid"] == pid and row["age"] < timeout and (control or row["pipActive"])
        failed = failed or not alive
        print(f"elapsed={elapsed}s alive={alive} appState={row and row['appState']} "
              f"heartbeatAge={row and round(row['age'], 1)}s pipActive={row and row['pipActive']}", flush=True)
finally:
    summary = dict(pid=pid, duration=duration, control=control, failed=failed, samples=rows)
    (output / f"summary-{"control-" if control else ""}{duration}.json").write_text(json.dumps(summary, indent=2))
    if not keep:
        devicectl("cleanup", "device", "process", "launch", "--device", device, "--terminate-existing", bundle)
if control:
    print("CONTROL " + ("was suspended or stopped without PiP" if failed else "kept serving without PiP; no PiP gain shown"))
    sys.exit(0)
print("FAILED: standby stopped serving in the background" if failed else "PASSED: standby kept serving in the background")
sys.exit(1 if failed else 0)
