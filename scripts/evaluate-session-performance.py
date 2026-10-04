#!/usr/bin/env python3
"""Aggregate body-free session metrics from JSONL or macOS log-show NDJSON."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import sys

TERMINALS = {"inserted", "copied", "uncertain", "notDelivered", "returnedText", "cancelled", "failed"}
STAGES = {"queue", "preparation", "tail", "transcription", "processing", "delivery"}
GENERATIONS = {"primary", "fallback", "factSupport", "image"}


def duration(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise ValueError("duration must be finite and non-negative")
    return value


def validate(event):
    if event["terminal"] not in TERMINALS:
        raise ValueError("unknown terminal")
    if event.get("releaseToTerminalMilliseconds") is not None:
        duration(event["releaseToTerminalMilliseconds"])
    for field, names in [("stages", STAGES), ("generations", GENERATIONS)]:
        if not isinstance(event[field], list):
            raise ValueError(f"{field} must be an array")
        for sample in event[field]:
            if sample["stage"] not in names:
                raise ValueError(f"unknown {field} stage")
            duration(sample["elapsedMilliseconds"])
            if field == "generations" and not isinstance(sample["failed"], bool):
                raise ValueError("generation failed must be boolean")


def distribution(values):
    values = sorted(values)
    return {"samples": len(values),
            "p50_ms": values[math.ceil(len(values) * .5) - 1] if values else None,
            "p95_ms": values[math.ceil(len(values) * .95) - 1] if values else None}


def evaluate(lines):
    events = {}
    for line in lines:
        if not line.strip():
            continue
        item = json.loads(line)
        if "eventMessage" in item:
            message = item["eventMessage"]
            if not message.startswith("utter.session.performance "):
                continue
            item = json.loads(message.removeprefix("utter.session.performance "))
        identity = item["sessionID"]
        if not isinstance(identity, str) or not identity:
            raise ValueError("sessionID must be a non-empty string")
        event = item["performance"]
        validate(event)
        if identity in events and events[identity] != event:
            raise ValueError("conflicting metrics for one session")
        events[identity] = event
    stages = defaultdict(list)
    generations = defaultdict(list)
    inserted = []
    terminals = Counter()
    for event in events.values():
        terminals[event["terminal"]] += 1
        if event["terminal"] != "inserted":
            continue
        value = event.get("releaseToTerminalMilliseconds")
        if value is not None:
            inserted.append(value)
        for name, field, destination in [("stage", "stages", stages), ("stage", "generations", generations)]:
            for sample in event[field]:
                destination[sample[name]].append(sample["elapsedMilliseconds"])
    return {"terminal_counts": dict(terminals), "confirmed_insertion": distribution(inserted),
            "stages": {key: distribution(values) for key, values in stages.items()},
            "generations": {key: distribution(values) for key, values in generations.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="JSONL or macOS log-show NDJSON; - reads stdin")
    args = parser.parse_args()
    try:
        if args.input == "-":
            result = evaluate(sys.stdin)
        else:
            with Path(args.input).open() as stream:
                result = evaluate(stream)
        print(json.dumps(result, indent=2, sort_keys=True))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
