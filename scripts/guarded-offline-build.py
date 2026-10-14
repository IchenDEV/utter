#!/usr/bin/env python3
"""Run one bounded command with a disk floor, process-group cleanup and evidence."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--evidence", type=Path, required=True)
parser.add_argument("--environment", type=Path, required=True)
parser.add_argument("--label", required=True)
parser.add_argument("--timeout", type=int, required=True)
parser.add_argument("--artifact-root", type=Path, help="Preserve successful build products before returning")
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
assert args.timeout > 0 and args.command and Path(args.label).name == args.label
args.evidence.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, **json.loads(args.environment.read_text()))
floor = 10 * 1024**3
stopping = False

def stop(signum, frame):
    global stopping
    stopping = True

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def snapshot():
    paths = [Path("Package.swift"), Path("Package.resolved")]
    for directory in ("Sources", "SourcesCLI", "Tests", "scripts"):
        paths.extend(p for p in Path(directory).rglob("*") if p.is_file() and "__pycache__" not in p.parts)
    files = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))}
    return {"files": files, "sha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}

def save(name, value):
    path = args.evidence / name
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    os.replace(temporary, path)

def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()

def preserve_artifacts():
    product_root = args.artifact_root.resolve(strict=True)
    binaries = [product_root / name for name in ("OpenType", "UtterVoiceEval", "UtterLexiconCheck")]
    assert all(p.is_file() for p in binaries), "Missing expected real build product"
    files = binaries + sorted(p for bundle in product_root.glob("*.bundle") for p in bundle.rglob("*") if p.is_file())
    assert all(not p.is_symlink() and p.resolve().is_relative_to(product_root) for p in files), "Unexpected resource symlink"
    assert shutil.disk_usage("/System/Volumes/Data").free - sum(p.stat().st_size for p in files) >= floor, "Data below artifact preservation floor"
    destination = args.evidence / (args.label + "-artifacts")
    destination.mkdir(exist_ok=False)
    witness = {"startedAt": now(), "productRoot": str(product_root), "preservedRoot": str(destination.resolve()), "files": {}}
    for source in files:
        assert shutil.disk_usage("/System/Volumes/Data").free >= floor, "Data below 10 GiB during artifact preservation"
        relative = source.relative_to(product_root)
        preserved = destination / relative
        preserved.parent.mkdir(parents=True, exist_ok=True)
        before = digest(source)
        shutil.copy2(source, preserved)
        copied = digest(preserved)
        after = digest(source)
        assert before == copied == after, "Build output changed during preservation: " + str(relative)
        witness["files"][str(relative)] = {"sha256": copied, "bytes": preserved.stat().st_size}
    witness["endedAt"] = now()
    witness["manifestSHA256"] = hashlib.sha256(json.dumps(witness["files"], sort_keys=True).encode()).hexdigest()
    return witness

row = {"label": args.label, "argv": args.command, "cwd": os.getcwd(), "startedAt": now(),
       "timeoutSeconds": args.timeout, "environment": json.loads(args.environment.read_text()),
       "capacitySamples": [], "sourceBefore": snapshot()}
save(args.label + "-command.json", row)
log = args.evidence / (args.label + ".log")
process = None
try:
    assert shutil.disk_usage("/System/Volumes/Data").free >= floor, "Data below 10 GiB"
    with log.open("wb") as output:
        process = subprocess.Popen(args.command, env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        row.update(pid=process.pid, pgid=process.pid)
        save(args.label + "-command.json", row)
        deadline = time.monotonic() + args.timeout
        heartbeat = 0
        while process.poll() is None:
            free = shutil.disk_usage("/System/Volumes/Data").free
            row["capacitySamples"].append({"at": now(), "dataFreeBytes": free})
            if free < floor or stopping or time.monotonic() >= deadline:
                row["stopReason"] = "low space" if free < floor else "interrupted" if stopping else "timeout"
                break
            if time.monotonic() >= heartbeat:
                print(json.dumps({"label": args.label, "pid": process.pid, "freeGiB": round(free / 1024**3, 2), "logBytes": log.stat().st_size}), flush=True)
                save(args.label + "-command.json", row)
                heartbeat = time.monotonic() + 30
            time.sleep(1)
finally:
    if process is not None:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=5)
        try:
            os.killpg(process.pid, 0)
            row["processGroupEnded"] = False
        except ProcessLookupError:
            row["processGroupEnded"] = True
        row["exitCode"] = process.returncode
    row.update(endedAt=now(), sourceAfter=snapshot())
    row["inputsChangedDuringCommand"] = row["sourceBefore"] != row["sourceAfter"]
    if args.artifact_root and row.get("exitCode") == 0 and row.get("processGroupEnded"):
        try:
            row["artifactWitness"] = preserve_artifacts()
            row["sourceAfterPreservation"] = snapshot()
            row["artifactWitness"]["sourceStableThroughPreservation"] = row["sourceBefore"] == row["sourceAfter"] == row["sourceAfterPreservation"]
            row["artifactWitness"]["sourceAfterSHA256"] = row["sourceAfter"]["sha256"]
        except Exception as error:
            row["artifactError"] = str(error)
    row["logSHA256"] = hashlib.sha256(log.read_bytes()).hexdigest() if log.exists() else None
    save(args.label + "-command.json", row)
    print(json.dumps({k: v for k, v in row.items() if k not in ("environment", "sourceBefore", "sourceAfter", "sourceAfterPreservation", "capacitySamples", "artifactWitness")}), flush=True)
raise SystemExit(0 if row.get("exitCode") == 0 and row.get("processGroupEnded") and "stopReason" not in row and "artifactError" not in row else 1)
