#!/usr/bin/env python3
"""Validate real SwiftPM source ownership and the approved import boundaries."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

CONTRACT_IMPORTS = {
    "UtterKeyboardBridge": {"Foundation"},
    "UtterRuntime": {"Foundation"},
    "UtterContracts": {"Foundation", "UtterRuntime"},
    "UtterMediaContracts": {"Foundation", "AVFoundation", "CoreGraphics", "UtterRuntime", "UtterContracts"},
    "UtterPresentationContracts": {"Foundation", "AppKit", "SwiftUI", "Combine", "UtterRuntime", "UtterContracts", "UtterMediaContracts"},
}
CONTRACTS = set(CONTRACT_IMPORTS)
COMPOSITION_IMPORTS = {"UtterMobile": CONTRACTS | {"UtterData", "UtterProcessing", "UtterSession", "UtterAppleSpeech", "UtterModels", "UtterWhisper", "UtterMLX"}}
IMPORT = re.compile(r"^\s*(?:@\w+\s+)*import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(\w+)", re.MULTILINE)


def violations(root, description):
    owners = {}
    errors = []
    for target in description["targets"]:
        name = target["name"]
        swift_filenames = {}
        for source in target.get("sources", []):
            path = (root / target["path"] / source).resolve()
            if path in owners:
                errors.append(f"{path}: owned by both {owners[path]} and {name}")
            owners[path] = name
            if path.suffix == ".swift":
                filename = path.name.casefold()
                if filename in swift_filenames:
                    errors.append(f"{name}: duplicate Swift filename {path.name} in {swift_filenames[filename]} and {path}")
                swift_filenames[filename] = path
            if not path.is_file():
                errors.append(f"{path}: missing declared source")
                continue
            if not name.startswith("Utter") or name.endswith("Tests") or target.get("type") == "executable":
                continue
            for imported in IMPORT.findall(path.read_text()):
                if name in CONTRACT_IMPORTS and imported not in CONTRACT_IMPORTS[name]:
                    errors.append(f"{path}: {name} cannot import {imported}")
                elif name in COMPOSITION_IMPORTS and imported.startswith("Utter") and imported not in COMPOSITION_IMPORTS[name]:
                    errors.append(f"{path}: {name} cannot compose {imported}")
                elif name not in CONTRACTS and name not in COMPOSITION_IMPORTS and name != "UtterBuiltins" and imported.startswith("Utter") and imported not in CONTRACTS:
                    errors.append(f"{path}: {name} cannot import sibling implementation {imported}")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--description", type=Path)
    args = parser.parse_args()
    if args.description:
        description = json.loads(args.description.read_text())
    else:
        description = json.loads(subprocess.check_output(["swift", "package", "describe", "--type", "json"], cwd=args.root))
    errors = violations(args.root, description)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("Swift module boundaries passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
