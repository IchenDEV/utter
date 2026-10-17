#!/usr/bin/env python3
"""Record sanitized nested-code signature facts for an app bundle (read-only)."""
import json, plistlib, re, subprocess, sys
from pathlib import Path

app = Path(sys.argv[1])

def run(*args):
    p = subprocess.run(args, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr

def sig_fields(path):
    _, out = run("codesign", "-dvvv", str(path))
    keep = {}
    for line in out.splitlines():
        for key in ("Identifier", "TeamIdentifier", "Timestamp", "Signature"):
            if line.startswith(key + "="):
                keep[key] = line.split("=", 1)[1]
        m = re.match(r"CodeDirectory .*flags=(\S+)", line)
        if m:
            keep["flags"] = m.group(1)
        if line.startswith("Authority="):
            keep.setdefault("authority", []).append(line.split("=", 1)[1])
    return keep

def entitlements(path):
    p = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(path)],
                       capture_output=True, text=True)
    start = p.stdout.find("<?xml")
    if start < 0:
        return None
    end = p.stdout.rfind("</plist>")
    try:
        return plistlib.loads(p.stdout[start:end + len("</plist>")].encode())
    except Exception:
        return "unparseable"

def macho_info(path):
    rc, out = run("lipo", "-archs", str(path))
    archs = out.strip() if rc == 0 else None
    rpaths = []
    if archs:
        _, o = run("otool", "-l", str(path))
        lines = o.splitlines()
        for i, l in enumerate(lines):
            if "cmd LC_RPATH" in l:
                rpaths.append(lines[i + 2].split("path ", 1)[1].split(" (offset")[0].strip())
    return archs, rpaths

entries = {}
targets = [app, app / "Contents/MacOS/Utter", app / "Contents/MacOS/opentype-cli"]
targets += sorted((app / "Contents/Resources").glob("*.bundle"))
for t in targets:
    rel = "Utter.app" if t == app else str(t.relative_to(app))
    archs, rpaths = macho_info(t) if t.is_file() else (None, [])
    entries[rel] = {
        "signature": sig_fields(t),
        "entitlements": entitlements(t),
        "archs": archs,
        "rpaths": rpaths,
    }
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
doc = {
    "bundleIdentifier": info.get("CFBundleIdentifier"),
    "shortVersion": info.get("CFBundleShortVersionString"),
    "entries": entries,
}
json.dump(doc, sys.stdout, indent=2, sort_keys=True, default=str)
print()
