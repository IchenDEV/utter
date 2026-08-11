#!/usr/bin/env python3
"""Evaluate raw ASR and optional post-processed transcripts from JSONL."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

from voice_quality_metrics import evaluate


REQUIRED_FIELDS = ("id", "language", "faithful_reference", "asr_text")
TEXT_FIELDS = (
    "language",
    "faithful_reference",
    "asr_text",
    "sendable_reference",
    "processed_text",
)
LATENCY_FIELDS = ("asr_latency_ms", "processing_latency_ms")


class CorpusError(ValueError):
    """A JSONL record does not conform to the evaluator schema."""


def validate_record(value: Any, line_number: int) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise CorpusError(f"line {line_number}: expected a JSON object")
    missing = [field for field in REQUIRED_FIELDS if field not in value]
    if missing:
        raise CorpusError(
            f"line {line_number}: missing required field(s): {', '.join(missing)}"
        )
    record = dict(value)
    identifier = record["id"]
    if isinstance(identifier, bool) or not isinstance(identifier, (str, int, float)):
        raise CorpusError(f"line {line_number}: id must be a string or number")
    record["id"] = str(identifier)
    if not record["id"].strip():
        raise CorpusError(f"line {line_number}: id must not be empty")
    for field in TEXT_FIELDS:
        if field in record and not isinstance(record[field], str):
            raise CorpusError(f"line {line_number}: {field} must be a string")
    if not record["language"].strip():
        raise CorpusError(f"line {line_number}: language must not be empty")
    terms = record.get("terms", [])
    if not isinstance(terms, list) or any(
        not isinstance(term, str) or not term for term in terms
    ):
        raise CorpusError(
            f"line {line_number}: terms must be an array of non-empty strings"
        )
    record["terms"] = terms
    for field in LATENCY_FIELDS:
        if field not in record:
            continue
        latency = record[field]
        if (
            isinstance(latency, bool)
            or not isinstance(latency, (int, float))
            or not math.isfinite(float(latency))
            or latency < 0
        ):
            raise CorpusError(
                f"line {line_number}: {field} must be a finite non-negative number"
            )
        record[field] = float(latency)
    return record


def load_records(path: str) -> list[dict[str, Any]]:
    stream = sys.stdin if path == "-" else Path(path).open(encoding="utf-8")
    records: list[dict[str, Any]] = []
    identifiers: set[str] = set()
    try:
        for line_number, line in enumerate(stream, start=1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError as error:
                raise CorpusError(
                    f"line {line_number}: invalid JSON: {error.msg}"
                ) from error
            record = validate_record(value, line_number)
            if record["id"] in identifiers:
                raise CorpusError(
                    f"line {line_number}: duplicate id {record['id']!r}"
                )
            identifiers.add(record["id"])
            records.append(record)
    finally:
        if stream is not sys.stdin:
            stream.close()
    if not records:
        raise CorpusError("corpus contains no records")
    return records


def format_rate(metric: dict[str, Any], numerator: str, denominator: str) -> str:
    rate = metric["rate"]
    if rate is None:
        return "n/a"
    return f"{rate * 100:.2f}% ({metric[numerator]}/{metric[denominator]})"


def render_view(label: str, view: dict[str, Any]) -> list[str]:
    lines = [f"{label} ({view['records']} records)"]
    lines.append(
        "  CER overall: "
        + format_rate(view["cer"], "distance", "reference_units")
    )
    for language, metric in view["cer_by_language"].items():
        lines.append(
            f"  CER {language}: "
            + format_rate(metric, "distance", "reference_units")
        )
    lines.append(
        "  English WER: "
        + format_rate(view["english_wer"], "distance", "reference_units")
    )
    hallucination = view["empty_reference_hallucination"]
    lines.append(
        "  Empty-reference hallucination: "
        f"{hallucination['hallucinated_characters']} characters, "
        f"{hallucination['records_with_hallucination']}/"
        f"{hallucination['empty_reference_records']} records"
    )
    lines.append(
        "  Terms exact: "
        + format_rate(view["terms_exact"], "matched", "expected")
    )
    for category in ("number", "url", "email", "path", "combined"):
        fidelity = view["protected_fidelity"][category]
        lines.append(
            f"  {category} fidelity: "
            + format_rate(
                fidelity, "exact_records", "evaluated_records"
            )
            + f", +{fidelity['insertions']}/-{fidelity['deletions']}"
        )
    return lines


def render_text(report: dict[str, Any]) -> str:
    lines = [f"Voice quality evaluation ({report['corpus_records']} records)"]
    lines.extend(render_view("ASR vs faithful reference", report["asr"]))
    lines.extend(render_view("Processed vs sendable reference", report["processed"]))
    lines.append("Latency (ms)")
    for phase in ("asr", "processing", "total"):
        metric = report["latency_ms"][phase]
        p50 = "n/a" if metric["p50"] is None else f"{metric['p50']:.2f}"
        p95 = "n/a" if metric["p95"] is None else f"{metric['p95']:.2f}"
        lines.append(
            f"  {phase}: p50={p50}, p95={p95} ({metric['records']} records)"
        )
    return "\n".join(lines)


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Evaluate Utter ASR and post-processing quality from JSONL.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""JSONL schema (one object per non-empty line):
  Required:
    id                    unique string or number
    language              BCP-47-like tag; metrics group by base language
    faithful_reference    literal spoken-content gold text; may be empty
    asr_text              raw ASR output
  Optional:
    sendable_reference    edited gold text for processed_text
    processed_text        post-processed output; falls back to faithful_reference
                          as its gold text when sendable_reference is absent
    terms                 array of preferred spellings expected verbatim
    asr_latency_ms        finite non-negative number
    processing_latency_ms finite non-negative number

CER uses NFKC text with whitespace removed and preserves case/punctuation.
English WER uses case-folded word tokens and ignores punctuation. Empty-reference
insertions contribute to aggregate CER and are also reported separately. Protected
fidelity requires the exact per-record multiset of numbers, URLs, emails, and
paths; additions and deletions both fail the record. Quoting is recommended for
directory paths that contain spaces and have no filename extension.

Example:
  scripts/evaluate-voice-quality.py \\
    docs/superpowers/specs/voice-quality-corpus.example.jsonl
  scripts/evaluate-voice-quality.py --format json corpus.jsonl
  cat corpus.jsonl | scripts/evaluate-voice-quality.py --format json -""",
    )
    parser.add_argument("corpus", help="UTF-8 JSONL corpus path, or - for stdin")
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="output format (default: text)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(argv)
    try:
        report = evaluate(load_records(arguments.corpus))
    except (CorpusError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    if arguments.format == "json":
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(render_text(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
