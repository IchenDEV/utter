#!/usr/bin/env python3

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "evaluate-voice-quality.py"


class VoiceQualityEvaluatorTests(unittest.TestCase):
    def run_cli(self, records):
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", encoding="utf-8") as fixture:
            for record in records:
                fixture.write(json.dumps(record, ensure_ascii=False) + "\n")
            fixture.flush()
            return subprocess.run(
                [sys.executable, str(SCRIPT), "--format", "json", fixture.name],
                check=False,
                capture_output=True,
                text=True,
            )

    def test_reports_asr_processed_fidelity_hallucination_and_latency(self):
        exact = (
            "OpenType 2.5 访问 https://example.com，发到 test@example.com，"
            "路径 /tmp/demo.txt"
        )
        result = self.run_cli(
            [
                {
                    "id": "synthetic-zh-1",
                    "language": "zh-CN",
                    "faithful_reference": exact,
                    "asr_text": exact,
                    "sendable_reference": exact,
                    "processed_text": exact,
                    "terms": ["OpenType"],
                    "asr_latency_ms": 100,
                    "processing_latency_ms": 20,
                },
                {
                    "id": "synthetic-en-1",
                    "language": "en-US",
                    "faithful_reference": "hello world",
                    "asr_text": "hello brave world",
                    "asr_latency_ms": 200,
                },
                {
                    "id": "synthetic-silence-1",
                    "language": "zh",
                    "faithful_reference": "",
                    "asr_text": "幻觉",
                    "asr_latency_ms": 300,
                },
            ]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["corpus_records"], 3)
        self.assertEqual(report["asr"]["english_wer"]["rate"], 0.5)
        self.assertEqual(
            report["asr"]["empty_reference_hallucination"][
                "hallucinated_characters"
            ],
            2,
        )
        self.assertEqual(report["asr"]["terms_exact"]["rate"], 1.0)
        for category in ("number", "url", "email", "path", "combined"):
            self.assertEqual(
                report["asr"]["protected_fidelity"][category]["rate"], 1.0
            )
            self.assertEqual(
                report["asr"]["protected_fidelity"][category]["insertions"], 0
            )
            self.assertEqual(
                report["asr"]["protected_fidelity"][category]["deletions"], 0
            )
        self.assertEqual(report["processed"]["cer"]["rate"], 0.0)
        self.assertEqual(report["latency_ms"]["asr"]["p50"], 200.0)
        self.assertEqual(report["latency_ms"]["asr"]["p95"], 290.0)

    def test_fidelity_rejects_added_numbers_and_changed_unicode_space_path(self):
        result = self.run_cli(
            [
                {
                    "id": "added-number",
                    "language": "en",
                    "faithful_reference": "version 2",
                    "asr_text": "version 2 plus 999",
                },
                {
                    "id": "changed-path",
                    "language": "zh",
                    "faithful_reference": "打开 /Users/陈丽/My File.txt。",
                    "asr_text": "打开 /Users/陈丽/My Other.txt。",
                },
            ]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)["asr"]["protected_fidelity"]
        self.assertEqual(report["number"]["rate"], 0.0)
        self.assertEqual(report["number"]["insertions"], 1)
        self.assertEqual(report["path"]["rate"], 0.0)
        self.assertEqual(report["path"]["insertions"], 1)
        self.assertEqual(report["path"]["deletions"], 1)
        self.assertEqual(report["combined"]["rate"], 0.0)

    def test_fidelity_preserves_sentence_email_opaque_paths_and_quotes(self):
        result = self.run_cli(
            [
                {
                    "id": "sentence-email",
                    "language": "zh",
                    "faithful_reference": "联系 test@example.com.",
                    "asr_text": "联系 nobody@example.com.",
                },
                {
                    "id": "opaque-path",
                    "language": "zh",
                    "faithful_reference": "打开 /tmp/①.txt",
                    "asr_text": "打开 /tmp/1.txt",
                },
                {
                    "id": "quoted-path",
                    "language": "zh",
                    "faithful_reference": '运行 "/tmp/My File.txt"',
                    "asr_text": "运行 /tmp/My File.txt",
                },
                {
                    "id": "balanced-url",
                    "language": "en",
                    "faithful_reference": (
                        "Read https://en.wikipedia.org/wiki/Function_(mathematics)"
                    ),
                    "asr_text": (
                        "Read https://en.wikipedia.org/wiki/Function_(mathematics"
                    ),
                },
            ]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)["asr"]["protected_fidelity"]
        self.assertEqual(report["email"]["rate"], 0.0)
        self.assertEqual(report["email"]["insertions"], 1)
        self.assertEqual(report["email"]["deletions"], 1)
        self.assertEqual(report["path"]["rate"], 0.0)
        self.assertEqual(report["path"]["insertions"], 2)
        self.assertEqual(report["path"]["deletions"], 2)
        self.assertEqual(report["url"]["rate"], 0.0)
        self.assertEqual(report["url"]["insertions"], 1)
        self.assertEqual(report["url"]["deletions"], 1)
        self.assertEqual(report["combined"]["rate"], 0.0)

    def test_fidelity_rejects_reordered_number_ownership(self):
        result = self.run_cli(
            [
                {
                    "id": "reordered-numbers",
                    "language": "en",
                    "faithful_reference": "Alice 2, Bob 3",
                    "asr_text": "Alice 3, Bob 2",
                }
            ]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)["asr"]["protected_fidelity"]
        self.assertEqual(report["number"]["rate"], 0.0)
        self.assertEqual(report["combined"]["rate"], 0.0)

    def test_rejects_missing_required_field_with_line_number(self):
        result = self.run_cli(
            [{"id": "broken", "language": "zh", "faithful_reference": "文本"}]
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("line 1", result.stderr)
        self.assertIn("asr_text", result.stderr)

    def test_help_documents_schema(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--help"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("JSONL schema", result.stdout)
        self.assertIn("faithful_reference", result.stdout)


if __name__ == "__main__":
    unittest.main()
