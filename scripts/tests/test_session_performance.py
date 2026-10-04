import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("performance", Path(__file__).parents[1] / "evaluate-session-performance.py")
performance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(performance)


def event(identity, terminal, elapsed):
    return {"sessionID": identity, "performance": {
        "terminal": terminal, "releaseToTerminalMilliseconds": elapsed,
        "stages": [{"stage": "delivery", "elapsedMilliseconds": 300}],
        "generations": [{"stage": "primary", "elapsedMilliseconds": 50, "failed": False}]}}


class SessionPerformanceTests(unittest.TestCase):
    def test_only_confirmed_insertion_contributes_to_latency(self):
        rows = [event("insert", "inserted", 500), event("copy", "copied", 10), event("uncertain", "uncertain", 20)]
        report = performance.evaluate(map(json.dumps, rows))
        self.assertEqual(report["confirmed_insertion"], {"samples": 1, "p50_ms": 500, "p95_ms": 500})
        self.assertEqual(report["terminal_counts"], {"inserted": 1, "copied": 1, "uncertain": 1})
        self.assertEqual(report["stages"]["delivery"]["samples"], 1)

    def test_log_show_events_and_duplicate_exports_count_once(self):
        row = event("one", "inserted", 400)
        lines = [json.dumps({"eventMessage": "other log"}), json.dumps(row),
                 json.dumps({"eventMessage": "utter.session.performance " + json.dumps(row)})]
        self.assertEqual(performance.evaluate(lines)["confirmed_insertion"]["samples"], 1)

    def test_unmeasured_session_is_not_reported_as_zero(self):
        report = performance.evaluate([json.dumps(event("one", "inserted", None))])
        self.assertEqual(report["confirmed_insertion"]["samples"], 0)
        self.assertIsNone(report["confirmed_insertion"]["p95_ms"])

    def test_invalid_or_conflicting_metrics_are_rejected(self):
        for field, value in [("terminal", "success"), ("releaseToTerminalMilliseconds", -1)]:
            row = event("one", "inserted", 400)
            row["performance"][field] = value
            with self.assertRaises(ValueError):
                performance.evaluate([json.dumps(row)])
        for value in [True, -1, float("inf"), float("nan")]:
            row = event("one", "failed", 400)
            row["performance"]["stages"][0]["elapsedMilliseconds"] = value
            with self.assertRaises(ValueError):
                performance.evaluate([json.dumps(row)])
        with self.assertRaises(ValueError):
            performance.evaluate(map(json.dumps, [event("one", "inserted", 400), event("one", "copied", 400)]))
