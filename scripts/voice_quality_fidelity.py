"""Protected-token extraction and exact-fidelity metrics."""

from __future__ import annotations

import re
import unicodedata
from collections import Counter
from typing import Any, Iterable


URL_RE = re.compile(r"(?i)\b(?:https?://|www\.)[^\s<>\"']+")
EMAIL_RE = re.compile(
    r"(?i)(?<![\w.+-])[\w.!#$%&'*+/=?^`{|}~-]+@"
    r"(?:(?:[^\W_]|-)+\.)+(?:[^\W_\d]{2,}|xn--[a-z0-9-]+)(?![\w-])"
)
QUOTED_PATH_RE = re.compile(
    r"""(?P<quote>["'])(?:~|\.\.?|/|[A-Za-z]:\\|\\\\)[^"'\r\n]+(?P=quote)"""
)
SPACED_UNIX_FILE_PATH_RE = re.compile(
    r"""(?<![A-Za-z0-9_])(?:~|\.\.?|/)[^,;!?，。；！？<>\r\n"']*?"""
    r"""\.[A-Za-z0-9]{1,16}(?=$|[\s,;!?，。；！？)\]}])"""
)
UNIX_PATH_RE = re.compile(
    r"""(?<![A-Za-z0-9_])(?:~|\.\.?|/)"""
    r"""(?:[^\s,;!?，。；！？<>\r\n"']+/)*"""
    r"""[^\s,;!?，。；！？<>\r\n"']+"""
)
WINDOWS_PATH_RE = re.compile(
    r"(?i)(?<![A-Za-z0-9_])[a-z]:\\(?:[^\\\s]+\\)*[^\\\s]+"
)
UNC_PATH_RE = re.compile(r"\\\\[^\\\s]+\\(?:[^\\\s]+\\)*[^\\\s]+")
RELATIVE_FILE_PATH_RE = re.compile(
    r"(?<![\w./-])(?:[A-Za-z0-9_][A-Za-z0-9._-]*/)+"
    r"[A-Za-z0-9_][A-Za-z0-9._-]*\.[A-Za-z][A-Za-z0-9]{0,15}"
    r"(?=$|[\s,;!?，。；！？)\]}])"
)
BARE_FILE_PATH_RE = re.compile(
    r"(?<![\w./-])[A-Za-z0-9_][A-Za-z0-9._-]*"
    r"\.[A-Za-z][A-Za-z0-9]{0,15}(?=$|[\s,;!?，。；！？)\]}])"
)
NUMBER_RE = re.compile(r"[+-]?\d+(?:[.,:/-]\d+)*(?:[%％])?")
CATEGORIES = ("number", "url", "email", "path")


def overlaps(span: tuple[int, int], occupied: list[tuple[int, int]]) -> bool:
    return any(span[0] < end and start < span[1] for start, end in occupied)


def trim_entity_punctuation(value: str) -> str:
    always_trailing = ".,;:!?，。；：！？"
    pairs = {")": "(", "）": "（", "]": "[", "】": "【", "}": "{"}
    while value:
        last = value[-1]
        if last in always_trailing:
            value = value[:-1]
            continue
        opening = pairs.get(last)
        if opening is None or value.count(last) <= value.count(opening):
            break
        value = value[:-1]
    return value


def extracted_protected_entities(
    text: str,
) -> tuple[dict[str, list[str]], list[tuple[str, str]]]:
    normalized = unicodedata.normalize("NFC", text)
    entities: dict[str, list[str]] = {category: [] for category in CATEGORIES}
    occupied: list[tuple[int, int]] = []
    ordered: list[tuple[int, str, str]] = []
    patterns = (
        ("url", URL_RE, None),
        ("email", EMAIL_RE, None),
        ("path", QUOTED_PATH_RE, None),
        ("path", SPACED_UNIX_FILE_PATH_RE, None),
        ("path", UNIX_PATH_RE, None),
        ("path", WINDOWS_PATH_RE, None),
        ("path", UNC_PATH_RE, None),
        ("path", RELATIVE_FILE_PATH_RE, None),
        ("path", BARE_FILE_PATH_RE, None),
        ("number", NUMBER_RE, None),
    )
    for category, pattern, value_group in patterns:
        for match in pattern.finditer(normalized):
            start, end = match.span(value_group) if value_group else match.span()
            value = (
                match.group(value_group) if value_group else match.group()
            )
            value = trim_entity_punctuation(value)
            if category == "number":
                value = unicodedata.normalize("NFKC", value)
            end = start + len(value)
            if not value or overlaps((start, end), occupied):
                continue
            entities[category].append(value)
            ordered.append((start, category, value))
            occupied.append((start, end))
    ordered.sort(key=lambda item: item[0])
    return entities, [(category, value) for _, category, value in ordered]


def protected_entities(text: str) -> dict[str, list[str]]:
    return extracted_protected_entities(text)[0]


def empty_category_metric() -> dict[str, Any]:
    return {
        "matched": 0,
        "expected": 0,
        "observed": 0,
        "insertions": 0,
        "deletions": 0,
        "exact_records": 0,
        "evaluated_records": 0,
        "rate": None,
        "recall": None,
        "precision": None,
    }


def finalize_category_metric(values: dict[str, Any]) -> None:
    values["rate"] = (
        values["exact_records"] / values["evaluated_records"]
        if values["evaluated_records"]
        else None
    )
    values["recall"] = (
        values["matched"] / values["expected"] if values["expected"] else None
    )
    values["precision"] = (
        values["matched"] / values["observed"] if values["observed"] else None
    )


def fidelity_metric(
    pairs: Iterable[tuple[dict[str, Any], str, str]]
) -> dict[str, Any]:
    totals = {category: empty_category_metric() for category in CATEGORIES}
    combined_exact_records = combined_evaluated_records = 0
    for _, reference, hypothesis in pairs:
        expected_entities, expected_sequence = extracted_protected_entities(reference)
        actual_entities, actual_sequence = extracted_protected_entities(hypothesis)
        record_has_entities = False
        for category in CATEGORIES:
            expected_values = expected_entities[category]
            observed_values = actual_entities[category]
            expected = Counter(expected_values)
            observed = Counter(observed_values)
            matched = sum((expected & observed).values())
            expected_count = sum(expected.values())
            observed_count = sum(observed.values())
            values = totals[category]
            values["matched"] += matched
            values["expected"] += expected_count
            values["observed"] += observed_count
            values["deletions"] += expected_count - matched
            values["insertions"] += observed_count - matched
            if expected or observed:
                record_has_entities = True
                values["evaluated_records"] += 1
                if expected_values == observed_values:
                    values["exact_records"] += 1
        if record_has_entities:
            combined_evaluated_records += 1
            combined_exact_records += expected_sequence == actual_sequence

    for values in totals.values():
        finalize_category_metric(values)

    combined = {
        key: sum(values[key] for values in totals.values())
        for key in (
            "matched",
            "expected",
            "observed",
            "insertions",
            "deletions",
        )
    }
    combined.update(
        {
            "exact_records": combined_exact_records,
            "evaluated_records": combined_evaluated_records,
        }
    )
    finalize_category_metric(combined)
    totals["combined"] = combined
    return totals
