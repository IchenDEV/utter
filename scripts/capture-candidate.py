#!/usr/bin/env python3
"""Capture current inputs before/after checks without overwriting historical evidence."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("--artifact", action="append", type=Path, default=[])
args = parser.parse_args()
artifacts = set(args.artifact)
for artifact in args.artifact:
    if artifact.parent.suffix in {".app", ".appex"}:
        artifacts.update(artifact.parent.glob("*.debug.dylib"))
        artifacts.add(artifact.parent / "Info.plist")
root = Path(__file__).resolve().parents[1]
def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=root)
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""): digest.update(block)
    return digest.hexdigest()
paths = sorted(set(git("ls-files", "-z", "--cached", "--others", "--exclude-standard").decode().split("\0")) - {""})
sources = {p: sha(root / p) for p in paths if (root / p).is_file() and (
    p.startswith(("Sources/", "iOS/", "Tests/", "scripts/", "Resources/", ".github/")) or
    p in {"AGENTS.md", "Package.swift", "Package.resolved"})}
head = git("rev-parse", "HEAD").strip()
worktree = hashlib.sha256(head + git("diff", "--binary", "HEAD"))
for path in sorted(git("ls-files", "-z", "--others", "--exclude-standard").decode().split("\0")):
    if path and not path.startswith(".local/") and (root / path).is_file():
        worktree.update(path.encode()); worktree.update((root / path).read_bytes())
report = {"capturedAt": datetime.now().astimezone().isoformat(), "head": head.decode(),
    "worktreeMethod": "HEAD + tracked binary diff + sorted untracked path/bytes; .local evidence and ignored caches excluded",
    "worktreeSHA256": worktree.hexdigest(), "sourceInputsSHA256": hashlib.sha256(
        json.dumps(sources, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
    "sourceInputs": sources, "artifacts": {str(p): sha(p) for p in sorted(artifacts)}}
args.output.parent.mkdir(parents=True, exist_ok=True)
with args.output.open("x") as stream: json.dump(report, stream, indent=2, ensure_ascii=False)
print(json.dumps({k: v for k, v in report.items() if k != "sourceInputs"}, indent=2))
