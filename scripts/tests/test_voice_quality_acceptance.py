import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from voice_quality_acceptance import acceptance_report


class AcceptanceTests(unittest.TestCase):
    def rows(self):
        rows = []
        for case_id, count, outcome in [("demo-clock", 5, "accepted"), ("custom-delete-01", 20, "accepted"), ("custom-added-fact-01", 20, "fallback")]:
            for attempt in range(count):
                rows.append({"case_id": case_id if case_id.startswith("demo-") else case_id + f"-{attempt}", "id": f"{case_id}-{attempt}", "outcome": outcome,
                             "constraints_pass": True, "semantic_review": "required"})
        return rows

    def manifest(self):
        return {"state": "completed", "completed_runs": 45, "expected_runs": 45,
                "expected_cases": {**{"demo-clock": 5}, **{f"custom-delete-01-{i}": 1 for i in range(20)},
                                   **{f"custom-added-fact-01-{i}": 1 for i in range(20)}}}

    def test_engineering_success_requires_separate_semantic_review(self):
        report = acceptance_report(self.rows(), self.manifest())
        self.assertTrue(report["engineering_criteria_pass"])
        self.assertFalse(report["acceptance_pass"])
        self.assertIsNone(report["added_facts"])
        self.assertIsNone(report["object_mismatches"])

    def test_missing_rows_and_partial_manifest_never_pass(self):
        for rows, manifest in [(self.rows()[:-1], self.manifest()), (self.rows(), None),
                               (self.rows(), {**self.manifest(), "state": "partial"})]:
            self.assertFalse(acceptance_report(rows, manifest)["acceptance_pass"])
            self.assertFalse(acceptance_report(rows, manifest)["complete"])

    def test_any_unsafe_candidate_admitted_fails_the_gate(self):
        rows = self.rows()
        rows[-1]["outcome"] = "accepted"
        report = acceptance_report(rows, self.manifest())
        self.assertFalse(report["engineering_criteria_pass"])
        self.assertEqual(report["unsafe_runs_not_rejected"], 1)

    def test_object_mismatch_cannot_be_hidden_by_lexical_metrics(self):
        rows = self.rows()
        for row in rows:
            row.update(semantic_review="approved", fact_review={"added_facts": [], "object_mismatches": []})
        self.assertTrue(acceptance_report(rows, self.manifest())["acceptance_pass"])
        rows[0]["fact_review"]["object_mismatches"] = ["Alice and Bob swapped their quantities"]
        report = acceptance_report(rows, self.manifest())
        self.assertEqual(report["object_mismatches"], 1)
        self.assertFalse(report["acceptance_pass"])

    def test_deletion_threshold_is_nineteen_of_twenty(self):
        rows = self.rows()
        rows[5]["outcome"] = "fallback"
        rows[5]["constraints_pass"] = False
        report = acceptance_report(rows, self.manifest())
        self.assertEqual(report["deletion_acceptance_rate"], .95)
        self.assertTrue(report["engineering_criteria_pass"])
        rows[6]["outcome"] = "fallback"
        rows[6]["constraints_pass"] = False
        self.assertFalse(acceptance_report(rows, self.manifest())["engineering_criteria_pass"])


if __name__ == "__main__":
    unittest.main()
