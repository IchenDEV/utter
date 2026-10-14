#!/usr/bin/env python3
"""Freeze the reviewed mobile increment without copying unrelated dirty work."""
import argparse
from datetime import datetime
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
base = "ed4234b41764be8346ae58cdc63011c8f26a0f1e"
assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip() == base

paths = [
    "Sources/UtterKeyboardBridge/BridgeMessages.swift", "Sources/UtterKeyboardBridge/SharedVoiceBridge.swift",
    "Sources/UtterKeyboardBridge/KeyboardSelectionEdit.swift", "Sources/UtterKeyboardBridge/KeyboardSelectionMessages.swift",
    "Sources/UtterKeyboardBridge/SharedVoiceBridge+Commands.swift", "Sources/UtterKeyboardBridge/SharedVoiceBridge+Selection.swift",
    "Sources/UtterMobile/LocalPolisher.swift", "Sources/UtterMobile/MobilePolisher.swift",
    "Sources/UtterMobile/MobileController.swift", "Sources/UtterMobile/MobileController+Runtime.swift",
    "Sources/UtterMobile/MobileController+KeyboardCapture.swift", "Sources/UtterMobile/MobileController+Selection.swift",
    "Sources/UtterMobile/MobileWorkflow.swift", "Sources/UtterMobile/MobileSelection.swift",
    "Tests/UtterKeyboardBridgeTests/KeyboardSelectionEditTests.swift", "Tests/UtterKeyboardBridgeTests/KeyboardSelectionBridgeTests.swift",
    "iOS/Keyboard/KeyboardController.swift", "iOS/Keyboard/KeyboardController+Dictation.swift",
    "iOS/Keyboard/KeyboardController+Selection.swift", "iOS/Keyboard/KeyboardSelectionOutput.swift",
    "iOS/Keyboard/KeyboardSelectionSurface.swift", "iOS/Keyboard/KeyboardState.swift",
    "iOS/Keyboard/KeyboardKeys.swift", "iOS/Keyboard/KeyboardView.swift", "iOS/App/VoiceHost.swift",
    "iOS/Shared/VoiceConfiguration.swift", "iOS/Resources/en.lproj/SelectionEdit.strings",
    "iOS/Resources/zh-Hans.lproj/SelectionEdit.strings", "iOS/Utter.xcodeproj/project.pbxproj",
    "scripts/check-keyboard-selection.py", "scripts/check-keyboard-selection-proxy.py",
    "scripts/check-mobile-selection.py", "scripts/fixtures/keyboard-selection-proxy.swift",
    "scripts/fixtures/mobile-selection.swift", "scripts/fixtures/mobile-selection-lifecycle.swift",
    "scripts/export-mobile-selection.py", "scripts/capture-candidate.py", "scripts/build-ios-return-probe.py",
]
def sha(data):
    return hashlib.sha256(data).hexdigest()

def original(path):
    result = subprocess.run(["git", "show", f"{base}:{path}"], cwd=root, capture_output=True)
    return result.stdout if result.returncode == 0 else None

def project(path, before, current):
    text = current.decode()
    if path == "iOS/App/VoiceHost.swift":
        text = before.decode().replace("command.action == .start", "command.action == .start || command.action == .startSelection")
    elif path == "iOS/Keyboard/KeyboardController.swift":
        text = text.replace(', hide: { [weak self] in self?.dismissKeyboard() }', '')
        text = text.replace("        refreshInputTraits()\n", "")
        text, count = re.subn(r"    func refreshInputTraits\(\) \{.*?\n    \}\n\n", "", text, flags=re.S)
        assert count == 1
    elif path == "iOS/Keyboard/KeyboardController+Dictation.swift":
        text = text.replace("        refreshInputTraits()\n", "")
    elif path == "iOS/Keyboard/KeyboardState.swift":
        text = text.replace("    @Published var returnKeyType: UIReturnKeyType = .default\n", "").replace("    @Published var returnEnabled = true\n", "")
    elif path == "iOS/Keyboard/KeyboardKeys.swift":
        line = next(line for line in text.splitlines(True) if "static let actionDisabled" in line)
        text = before.decode().replace("    static let recording", line + "    static let recording")
    elif path == "iOS/Keyboard/KeyboardView.swift":
        text = before.decode()
        text = text.replace("    private var statusKey: String {", "    private var restoreOwnsStatus: Bool { state.selectionRestoration?.isValid(at: Date()) == true }\n    private var statusKey: String {")
        block = "            place(m.sideMargin, m.rowTop(0), statusWidth, m.keyHeight) {\n                statusPill.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)\n            }"
        assert block in text
        text = text.replace(block, "            if !restoreOwnsStatus {\n" + "\n".join("    " + line for line in block.splitlines()) + "\n            }")
    elif path == "iOS/Utter.xcodeproj/project.pbxproj":
        # Keep only the native writer and selection UI/table IDs, not privacy or return-probe entries.
        text = "".join(line for line in text.splitlines(True) if not re.search(r"B20261008000000000000000[1-8]|B20261014000000000000000[12]", line))
    return text.encode()

entries, patch = [], []
for path in paths:
    before = original(path)
    current = (root / path).read_bytes()
    result = project(path, before, current)
    if result == before:
        continue
    for directory, data in [("base", before), ("sources", result), ("original-owned-backup", current)]:
        if data is not None:
            file = out / directory / path
            file.parent.mkdir(parents=True, exist_ok=True); file.write_bytes(data)
    diff = list(difflib.unified_diff((before or b"").decode().splitlines(True), result.decode().splitlines(True),
                                   fromfile=f"a/{path}" if before is not None else "/dev/null", tofile=f"b/{path}"))
    patch.append(f"diff --git a/{path} b/{path}\n" + ("new file mode 100644\n" if before is None else "") + "".join(diff))
    entries.append({"path": path, "baseSHA256": sha(before) if before is not None else None,
                    "resultSHA256": sha(result), "originalWorktreeSHA256": sha(current),
                    "projected": current != result, "source": f"sources/{path}",
                    "hunks": [line.strip() for line in diff if line.startswith("@@ ")]})

blob = "".join(patch).encode()
(out / "owned-mobile.patch").write_bytes(blob)
check = out / "apply-check"
check.mkdir()
for entry in entries:
    if entry["baseSHA256"] is not None:
        file = check / entry["path"]; file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes((out / "base" / entry["path"]).read_bytes())
command = ["git", "apply", "--unsafe-paths", "--directory", str(check), str(out / "owned-mobile.patch")]
subprocess.run(command[:2] + ["--check"] + command[2:], cwd="/tmp", check=True)
subprocess.run(command, cwd="/tmp", check=True)
assert all(sha((check / e["path"]).read_bytes()) == e["resultSHA256"] for e in entries)
subprocess.run(["plutil", "-lint", str(out / "sources/iOS/Utter.xcodeproj/project.pbxproj")], check=True)
manifest = {"schemaVersion": 1, "exportedAt": datetime.now().astimezone().isoformat(), "baseSHA": base,
            "status": "PENDING_PROJECTED_BUILD_AND_INDEPENDENT_REVIEW", "file": "owned-mobile.patch", "sha256": sha(blob),
            "entries": entries, "dryRunAndAppliedHashesMatch": True,
            "hunkPolicy": "Full new owned files; tracked hunks frozen in entries. Native views/glue mechanically projected to exclude old layout/PiP/scene experiment/privacy changes.",
            "T0Prerequisite": "Debug-only app capture/one-document attach and existing lease watcher APIs; no scene destruction, automatic return promise or Release path promotion.",
            "excluded": ["shared owners/r3 packet", "Models packet", "Package.swift", "Mac assets", "older keyboard layout/colour changes", "StandbyService PiP changes", "UtterPhoneApp/KeyboardReturnProbe", "privacy manifests", "entitlements/Plist", "older UI/device tests"],
            "limits": ["Physical device/native UI/microphone/model quality/automatic host return/focus unverified", "Parent final normal merge and exact combined-candidate rebuild required", "No commit, push, signing or device action"]}
(out / "packet.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps({k: v for k, v in manifest.items() if k != "entries"}, indent=2))
