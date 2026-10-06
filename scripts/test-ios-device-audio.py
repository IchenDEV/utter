#!/usr/bin/env python3
"""Play authorized fixed speech only after the physical-device capture marker."""
import os
from pathlib import Path
import re
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
output = root / ".build-ios"
arguments = sys.argv[1:]
standby = arguments[0] == "--standby"
if standby: arguments.pop(0)
run_name = arguments[0]
tests = arguments[1:] or [
    "testDeviceAppleChineseSpeech",
    "testDeviceAppleEnglishBackgroundSpeech",
    "testDeviceRecordingCancellationAndLimit",
    "testDeviceDownloadedModelSpeech",
]
assert re.fullmatch(r"[a-z0-9-]+", run_name)
assert all(re.fullmatch(r"test(?:Device|Real)[A-Za-z]+", test) for test in tests)
environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
products = "standby-device-probe/build/Build/Products" if standby else "ipad-device/Build/Products"
command = ["xcodebuild", "test-without-building", "-xctestrun",
           str(output / products / "UtteriOS_iphoneos27.0-arm64.xctestrun"),
           "-destination", "platform=iOS,id=00008130-00092D800891401C",
           "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
           "-maximum-test-execution-time-allowance",
           "2100" if "testDeviceConfuciusSpeech" in tests else "900" if "testDeviceStandbyKeyboardSpeechAfterIdle" in tests else "600",
           "-resultBundlePath", str(output / f"{run_name}.xcresult")]
command += [f"-only-testing:UtterSimulatorFlow/UtterSimulatorFlow/{test}" for test in tests]
played = 0
with (output / f"{run_name}.log").open("w") as log:
    with subprocess.Popen(command, cwd=root, env=environment, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, bufsize=1) as run:
        for line in run.stdout:
            log.write(line)
            log.flush()
            # `delay=` lets a test that blocks inside a long press have the speech begin after recording started.
            marker = re.fullmatch(r"UTTER_AUDIO_READY (zh|en|cancel) ([0-9.]+)(?: delay=([0-9.]+))?\s*", line)
            if marker:
                played += 1
                assert played <= 8, "Unexpected repeated capture markers"
                sample = "en" if marker[1] == "en" else "zh"
                if marker[3]:
                    assert float(marker[3]) <= 10, "Marker delay is capped at 10 seconds"
                    time.sleep(float(marker[3]))
                log.write(f"HOST_AUDIO_START {time.time():.3f} markerDelay={time.time() - float(marker[2]):.3f}\n")
                log.flush()
                print(f"Playing fixed {sample} sample ({played})", flush=True)
                subprocess.run(["/usr/bin/afplay", str(output / f"ipad-speech-{sample}.aiff")],
                               check=True, timeout=10)
                log.write(f"HOST_AUDIO_END {time.time():.3f}\n")
                log.flush()
            elif any(token in line for token in ("Test Case", "error:", "REAL_STANDBY", "DEVICE_SPEECH_RESULT", "DEVICE_MODEL_DOWNLOAD", "TEST FAILED", "TEST SUCCEEDED")):
                print(line.rstrip(), flush=True)
        result = run.wait()
print(f"Audio samples played: {played}; xcodebuild exit: {result}", flush=True)
sys.exit(result)
