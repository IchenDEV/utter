#!/usr/bin/env python3
"""Compare debugger-free standby; paused mode allows bounded foreground capture."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
output = root / ".build-ios/session-idle"
output.mkdir(parents=True, exist_ok=True)
device = "00008130-00092D800891401C"
bundle = "com.ichendev.utter.ios"
group = "group.com.ichendev.utter.ios"
environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
modes = sys.argv[1:] or ["control", "playback", "record"]
assert len(modes) == len(set(modes)) and all(mode in ["control", "playback", "record", "paused", "pip"] for mode in modes)


def command(name, *arguments):
    result = subprocess.run(["xcrun", "devicectl", "--timeout", "30", *arguments],
                            cwd=root, env=environment, text=True, capture_output=True, timeout=40)
    (output / f"{name}.log").write_text(result.stdout + result.stderr)
    result.check_returncode()


def launch(name, app, *arguments, terminate=False):
    options = ["--terminate-existing"] if terminate else []
    command(name, "device", "process", "launch", "--device", device,
            "--json-output", str(output / f"{name}.json"), *options, app, *arguments)


def journal(name):
    destination = output / f"{name}.json"
    command(name, "device", "copy", "from", "--device", device,
            "--domain-type", "appGroupDataContainer", "--domain-identifier", group,
            "--source", "Library/standby-journal.json", "--destination", str(destination))
    entries = json.loads(destination.read_text())
    assert entries and all(not row["engineRunning"] and row["completedFrames"] == 0 for row in entries)
    return entries


results = []
audio = None
try:
    for mode in modes:
        flags = ["--standby-autostart-pip"] if mode == "pip" else ["--standby-autostart"]
        if mode not in ["control", "pip"]:
            flags.append("--standby-session-only")
        if mode in ["record", "paused"]:
            flags.append("--standby-record-category")
        if mode == "paused":
            flags.append("--standby-paused-recorder")
        audio = None
        if mode == "paused":
            sample = root / ".build-ios/ipad-speech-zh.aiff"
            assert sample.is_file(), "Authorized fixed speech sample is missing"
        launch(f"{mode}-launch", bundle, *flags, terminate=True)
        if mode == "paused":
            pid = json.loads((output / f"{mode}-launch.json").read_text())["result"]["process"]["processIdentifier"]
            priming = None
            for attempt in range(6):
                try:
                    priming = journal(f"{mode}-priming-{attempt}")[-1]
                except subprocess.CalledProcessError as error:
                    message = (error.stdout or "") + (error.stderr or "")
                    if ("Failed to retrieve the file node for Library/standby-journal.json" not in message
                            or "CoreDeviceError error 7000" not in message):
                        raise
                    time.sleep(0.1)
                    continue
                if priming["pid"] == pid and priming["recorderRecording"]:
                    break
                time.sleep(0.1)
            assert priming and priming["pid"] == pid and priming["recorderRecording"], "Missed foreground recording window; do not play speech"
            audio = subprocess.Popen(["/usr/bin/afplay", str(sample)])
            print(f"paused: fixed speech start={time.time():.3f}; recording confirmed at={priming['time']:.3f}", flush=True)
        time.sleep(4 if mode == "paused" else 8 if mode == "pip" else 2)
        if audio is not None:
            assert audio.wait(timeout=10) == 0, "Fixed speech playback failed"
        initial = journal(f"{mode}-initial")[-1]
        expected = {"control": "ready", "pip": "active"}.get(mode, "session-only")
        launched = json.loads((output / f"{mode}-launch.json").read_text())["result"]["process"]["processIdentifier"]
        assert initial["pid"] == launched and initial["appState"] == 0, initial
        assert initial["phase"] == expected, initial
        if mode == "pip":
            assert initial["active"] and not initial["suspended"] and not initial["idleDisabled"], initial
        else:
            assert initial["sessionActivationSucceeded"] == (mode != "control"), initial
            assert initial["sessionOnly"] == (mode != "control") and initial["recordCategory"] == (mode in ["record", "paused"]), initial
            assert initial["pausedRecorder"] == (mode == "paused"), initial
            assert not initial["idleDisabled"] and not initial["active"] and not initial["suspended"], initial
            category = {"control": "SoloAmbient", "playback": "Playback", "record": "PlayAndRecord", "paused": "PlayAndRecord"}[mode]
            assert initial["audioCategory"] == "AVAudioSessionCategory" + category, initial
        if mode == "paused":
            assert initial["recorderPrepared"] and not initial["recorderRecording"] and initial["recorderTime"] > 1, initial
            print(f"paused: paused journal at={initial['time']:.3f}; recorded seconds={initial['recorderTime']:.3f}", flush=True)
        pid = initial["pid"]
        launch(f"{mode}-safari", "com.apple.mobilesafari")
        started = time.monotonic()
        print(f"{mode}: PID {pid}, {expected}; Safari activated without XCTest/debugger", flush=True)
        for elapsed in [15, 45, 85]:
            time.sleep(max(0, started + elapsed - time.monotonic()))
            entries = journal(f"{mode}-background-{elapsed}")
            assert all(row["pid"] == pid for row in entries), "Journal belongs to another process"
            assert any(row["appState"] == 2 for row in entries), "No observed background transition"
            assert all(not row.get("recorderRecording", False) for row in entries if row["appState"] == 2), "Recorder continued in background"
            if mode == "paused":
                assert all(abs(row["recorderTime"] - initial["recorderTime"]) < 0.01 for row in entries if row["appState"] == 2), "Paused recorder state changed"
            last = entries[-1]
            print(f"{mode}: elapsed={elapsed}, lastState={last['appState']}, "
                  f"ticks={last['backgroundTicks']}, journalAge={time.time() - last['time']:.1f}s", flush=True)
        # Preserve the last background sample before bringing the app to the foreground.
        background = entries
        launch(f"{mode}-resume", bundle)
        time.sleep(2)
        resumed = journal(f"{mode}-resumed")[-1]
        assert resumed["pid"] == pid, "Process restarted; cannot attribute the gap to suspension"
        assert resumed["appState"] == 0, "App did not resume in foreground"
        result = dict(mode=mode, pid=pid, observedSeconds=time.monotonic() - started,
                      backgroundTailAge=time.time() - background[-1]["time"],
                      backgroundTicks=resumed["backgroundTicks"], backgroundSeconds=resumed["backgroundSeconds"],
                      backgroundMaxGap=resumed["backgroundMaxGap"], audioCategory=initial["audioCategory"])
        results.append(result)
        (output / ("summary-" + "-".join(modes) + ".json")).write_text(json.dumps(results, indent=2))
        print(json.dumps(result), flush=True)
        launch(f"{mode}-cleanup", bundle, "--standby-cleanup", terminate=True)
        time.sleep(1)
finally:
    original_error = sys.exception()
    if audio is not None and audio.poll() is None:
        audio.terminate()
        audio.wait(timeout=3)
    try:
        launch("final-cleanup", bundle, "--standby-cleanup", terminate=True)
    except Exception as cleanup_error:
        print(f"Probe cleanup failed: {cleanup_error}", file=sys.stderr)
        if original_error is None:
            raise
