"""Dependency-free transcript quality metrics used by the evaluator CLI."""

from __future__ import annotations

import math
import re
import unicodedata
from collections import defaultdict
from typing import Any, Iterable, Sequence

from voice_quality_fidelity import fidelity_metric


def normalize_unicode(text: str) -> str:
    return unicodedata.normalize("NFKC", text)


def cer_units(text: str) -> list[str]:
    return [
        character
        for character in normalize_unicode(text)
        if not character.isspace()
    ]


def english_words(text: str) -> list[str]:
    normalized = normalize_unicode(text).casefold().replace("’", "'")
    return re.findall(r"[^\W_]+(?:'[^\W_]+)*", normalized, flags=re.UNICODE)


def edit_distance(reference: Sequence[str], hypothesis: Sequence[str]) -> int:
    if len(reference) > len(hypothesis):
        reference, hypothesis = hypothesis, reference
    previous = list(range(len(reference) + 1))
    for hypothesis_index, hypothesis_item in enumerate(hypothesis, start=1):
        current = [hypothesis_index]
        for reference_index, reference_item in enumerate(reference, start=1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[reference_index] + 1,
                    previous[reference_index - 1]
                    + (reference_item != hypothesis_item),
                )
            )
        previous = current
    return previous[-1]


def base_language(language: str) -> str:
    return re.split(r"[-_]", language.strip().casefold(), maxsplit=1)[0]


def comparison_pairs(
    records: Iterable[dict[str, Any]], processed: bool
) -> list[tuple[dict[str, Any], str, str]]:
    pairs = []
    for record in records:
        if processed:
            if "processed_text" not in record:
                continue
            reference = record.get(
                "sendable_reference", record["faithful_reference"]
            )
            hypothesis = record["processed_text"]
        else:
            reference = record["faithful_reference"]
            hypothesis = record["asr_text"]
        pairs.append((record, reference, hypothesis))
    return pairs


def error_metric(
    pairs: Iterable[tuple[dict[str, Any], str, str]], tokenizer
) -> dict[str, Any]:
    distance = reference_units = records = 0
    for _, reference, hypothesis in pairs:
        reference_tokens = tokenizer(reference)
        hypothesis_tokens = tokenizer(hypothesis)
        distance += edit_distance(reference_tokens, hypothesis_tokens)
        reference_units += len(reference_tokens)
        records += 1
    return {
        "records": records,
        "distance": distance,
        "reference_units": reference_units,
        "rate": distance / reference_units if reference_units else None,
    }


def term_occurs_exactly(text: str, term: str) -> bool:
    normalized_text = normalize_unicode(text)
    normalized_term = normalize_unicode(term)
    left = (
        r"(?<![A-Za-z0-9_])"
        if re.match(r"[A-Za-z0-9_]", normalized_term)
        else ""
    )
    right = (
        r"(?![A-Za-z0-9_])"
        if re.search(r"[A-Za-z0-9_]$", normalized_term)
        else ""
    )
    return (
        re.search(left + re.escape(normalized_term) + right, normalized_text)
        is not None
    )


def terms_metric(
    pairs: Iterable[tuple[dict[str, Any], str, str]]
) -> dict[str, Any]:
    expected = matched = 0
    for record, _, hypothesis in pairs:
        unique_terms = dict.fromkeys(
            normalize_unicode(term) for term in record["terms"]
        )
        for term in unique_terms:
            expected += 1
            matched += term_occurs_exactly(hypothesis, term)
    return {
        "matched": matched,
        "expected": expected,
        "rate": matched / expected if expected else None,
    }


def hallucination_metric(
    pairs: Iterable[tuple[dict[str, Any], str, str]]
) -> dict[str, int]:
    empty_records = hallucinated_records = hallucinated_characters = 0
    for _, reference, hypothesis in pairs:
        if cer_units(reference):
            continue
        empty_records += 1
        characters = len(cer_units(hypothesis))
        hallucinated_characters += characters
        hallucinated_records += characters > 0
    return {
        "empty_reference_records": empty_records,
        "records_with_hallucination": hallucinated_records,
        "hallucinated_characters": hallucinated_characters,
    }


def percentile(values: list[float], quantile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * quantile
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def latency_metric(values: list[float]) -> dict[str, Any]:
    return {
        "records": len(values),
        "p50": percentile(values, 0.5),
        "p95": percentile(values, 0.95),
    }


def evaluate_view(
    pairs: list[tuple[dict[str, Any], str, str]]
) -> dict[str, Any]:
    by_language: dict[
        str, list[tuple[dict[str, Any], str, str]]
    ] = defaultdict(list)
    for pair in pairs:
        by_language[base_language(pair[0]["language"])].append(pair)
    english = [
        pair for pair in pairs if base_language(pair[0]["language"]) == "en"
    ]
    return {
        "records": len(pairs),
        "cer": error_metric(pairs, cer_units),
        "cer_by_language": {
            language: error_metric(language_pairs, cer_units)
            for language, language_pairs in sorted(by_language.items())
        },
        "english_wer": error_metric(english, english_words),
        "empty_reference_hallucination": hallucination_metric(pairs),
        "terms_exact": terms_metric(pairs),
        "protected_fidelity": fidelity_metric(pairs),
    }


def evaluate(records: list[dict[str, Any]]) -> dict[str, Any]:
    asr_latencies = [
        record["asr_latency_ms"]
        for record in records
        if "asr_latency_ms" in record
    ]
    processing_latencies = [
        record["processing_latency_ms"]
        for record in records
        if "processing_latency_ms" in record
    ]
    total_latencies = [
        record["asr_latency_ms"] + record["processing_latency_ms"]
        for record in records
        if "asr_latency_ms" in record and "processing_latency_ms" in record
    ]
    return {
        "schema_version": 1,
        "corpus_records": len(records),
        "asr": evaluate_view(comparison_pairs(records, processed=False)),
        "processed": evaluate_view(comparison_pairs(records, processed=True)),
        "latency_ms": {
            "asr": latency_metric(asr_latencies),
            "processing": latency_metric(processing_latencies),
            "total": latency_metric(total_latencies),
        },
    }
