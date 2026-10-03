#!/usr/bin/env python3
"""Verify resources at their declared owners, in source or in an assembled app."""
import argparse
import json
import os
from pathlib import Path
import sys


def resource_errors(manifest, root, app=None):
    errors = []
    if manifest.get("schemaVersion") != 1:
        return ["unsupported resource manifest schema"]
    owners = set()
    for owner in manifest["bundles"]:
        name = owner["bundle"]
        if name in owners:
            errors.append(f"duplicate resource bundle {name}")
        owners.add(name)
        base = app / "Contents/Resources" / name / "Contents/Resources" if app else root / owner["source"]
        for relative in owner["files"]:
            path = base / relative
            allow_empty = relative in owner.get("allowEmpty", [])
            if not path.is_file() or (not allow_empty and path.stat().st_size == 0):
                errors.append(f"{owner['target']}: missing resource {relative}")
    if app:
        for relative in manifest["appFiles"] + manifest["executables"]:
            path = app / relative
            if not path.is_file() or path.stat().st_size == 0:
                errors.append(f"missing app artifact {relative}")
            elif relative in manifest["executables"] and not os.access(path, os.X_OK):
                errors.append(f"app helper is not executable: {relative}")
        for pattern in manifest["appGlobs"]:
            if not any(path.is_file() and path.stat().st_size > 0 for path in app.glob(pattern)):
                errors.append(f"missing app resource matching {pattern}")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    manifest = json.loads((args.root / "scripts/resource-bundles.json").read_text())
    errors = resource_errors(manifest, args.root, args.app)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("Owned resources passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
