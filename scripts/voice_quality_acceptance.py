"""Evaluate run completeness and explicitly annotated factual acceptance."""
from collections import Counter
from typing import Any

REQUIRED_DEMOS = {"demo-clock", "demo-pieces", "demo-items", "demo-entries", "demo-date",
                  "demo-clock-minutes", "demo-version", "demo-terms"}

def acceptance_report(records: list[dict[str, Any]], manifest: dict[str, Any] | None) -> dict[str, Any]:
    rows = [row for row in records if "case_id" in row]
    counts = Counter(row["case_id"] for row in rows)
    expected = (manifest or {}).get("expected_cases", {})
    complete = bool(
        rows and expected and counts == expected
        and manifest.get("state") == "completed"
        and manifest.get("completed_runs") == len(rows) == manifest.get("expected_runs")
    )
    demos = [row for row in rows if row["case_id"].startswith("demo-")]
    deletion = [row for row in rows if row["case_id"].startswith("custom-delete-")]
    unsafe = [row for row in rows if row["case_id"].startswith("custom-added-fact-")]
    constraints = all(row.get("constraints_pass") is True for row in rows
                      if not row["case_id"].startswith("custom-delete-"))
    demo_counts = Counter(row["case_id"] for row in demos)
    demo_pass = REQUIRED_DEMOS.issubset(demo_counts) and all(count >= 5 for count in demo_counts.values()) and all(
        row.get("outcome") == "accepted" and row.get("constraints_pass") is True for row in demos
    )
    deletion_accepted = sum(row.get("outcome") == "accepted" and row.get("constraints_pass") is True for row in deletion)
    deletion_rate = deletion_accepted / len(deletion) if deletion else None
    unsafe_accepted = sum(row.get("outcome") != "fallback" or row.get("constraints_pass") is not True for row in unsafe)
    reviewed = [row for row in rows if row.get("semantic_review") in {"approved", "rejected"} and "fact_review" in row]
    added = sum(len(row["fact_review"]["added_facts"]) for row in reviewed)
    mismatches = sum(len(row["fact_review"]["object_mismatches"]) for row in reviewed)
    semantics = len(reviewed) == len(rows) and bool(rows) and all(
        row["semantic_review"] == "approved" for row in reviewed
    ) and added == 0 and mismatches == 0
    engineering = complete and constraints and demo_pass and len({row["case_id"] for row in deletion}) >= 20 and deletion_rate >= .95 and len({row["case_id"] for row in unsafe}) >= 20 and unsafe_accepted == 0
    return {
        "complete": complete,
        "engineering_criteria_pass": engineering,
        "semantic_review_complete": len(reviewed) == len(rows) and bool(rows),
        "acceptance_pass": engineering and semantics,
        "demo_runs": len(demos),
        "demo_criteria_pass": demo_pass,
        "deletion_runs": len(deletion),
        "deletion_acceptance_rate": deletion_rate,
        "unsafe_runs": len(unsafe),
        "unsafe_runs_not_rejected": unsafe_accepted,
        "fact_reviewed_runs": len(reviewed),
        "added_facts": added if reviewed else None,
        "object_mismatches": mismatches if reviewed else None,
    }
