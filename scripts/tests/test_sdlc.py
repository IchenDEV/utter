#!/usr/bin/env python3

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "sdlc.py"
sys.path.insert(0, str(SCRIPT_PATH.parent))
SPEC = importlib.util.spec_from_file_location("sdlc", SCRIPT_PATH)
assert SPEC and SPEC.loader
SDLC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SDLC)


CONTENT = {
    "intent": """# Intent: Test
## Problem
Problem.
## Outcome
Outcome.
## Scope
Scope.
## Constraints
Constraints.
## Acceptance criteria
- It passes.
## Open questions
None.
""",
    "spec": """# Spec: Test
## Context
Context.
## Design
Design.
## Safety and failure modes
Failures.
## Test strategy
Tests.
## Rollout and rollback
Rollback.
""",
    "plan": """# Plan: Test
## Work items
- [x] Work.
## Verification plan
- [x] Verify.
## Human gates
Review.
""",
    "verification": """# Verification: Test
## Evidence
Passed.
## Acceptance criteria
- Passed.
## Residual risk
None.
## Decision
Ready for review.
""",
}


class SDLCValidationTests(unittest.TestCase):
    def make_bundle(self, root: Path, *, risk: str = "high", status: str = "verified", omit: str | None = None) -> Path:
        bundle_id = "2026-08-25-test-change"
        bundle = root / "docs" / "sdlc" / "changes" / bundle_id
        bundle.mkdir(parents=True)
        artifacts = {}
        for name, content in CONTENT.items():
            if name == omit:
                continue
            filename = f"{name}.md"
            artifacts[name] = filename
            (bundle / filename).write_text(content, encoding="utf-8")
        state = {
            "schemaVersion": 1,
            "id": bundle_id,
            "title": "Test change",
            "risk": risk,
            "status": status,
            "owners": ["maintainer"],
            "acceptanceCriteria": ["It passes."],
            "governedPaths": ["Sources/App/"],
            "artifacts": artifacts,
        }
        state_path = bundle / "state.json"
        state_path.write_text(json.dumps(state), encoding="utf-8")
        return state_path

    def test_verified_high_risk_bundle_is_valid(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = self.make_bundle(root)
            state, errors = SDLC.validate_bundle(state_path)
            self.assertEqual(state["status"], "verified")
            self.assertEqual(errors, [])

    def test_high_risk_bundle_requires_spec(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = self.make_bundle(Path(directory), omit="spec")
            _, errors = SDLC.validate_bundle(state_path)
            self.assertTrue(any("spec" in error for error in errors))

    def test_required_artifacts_must_be_distinct_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = self.make_bundle(Path(directory))
            state = json.loads(state_path.read_text(encoding="utf-8"))
            combined = state_path.parent / "combined.md"
            combined.write_text("\n".join(CONTENT.values()), encoding="utf-8")
            alias = state_path.parent / "alias.md"
            alias.symlink_to(combined.name)
            state["artifacts"] = {
                "intent": combined.name,
                "spec": f"./{combined.name}",
                "plan": str(combined.resolve()),
                "verification": alias.name,
            }
            state_path.write_text(json.dumps(state), encoding="utf-8")
            _, errors = SDLC.validate_bundle(state_path)
            self.assertTrue(any("distinct files" in error for error in errors))
            self.assertTrue(any("safe relative path" in error for error in errors))
            self.assertTrue(any("symlinks" in error for error in errors))

    def test_source_change_requires_changed_bundle(self) -> None:
        errors = SDLC.enforce_changed_files(["Sources/App/AppState.swift"], {})
        self.assertEqual(len(errors), 1)

    def test_verified_state_satisfies_governed_change(self) -> None:
        state_path = Path("docs/sdlc/changes/2026-08-25-test-change/state.json")
        paths = [
            "Sources/App/AppState.swift",
            "docs/sdlc/changes/2026-08-25-test-change/verification.md",
        ]
        states = {
            state_path: {
                "status": "verified",
                "risk": "medium",
                "governedPaths": ["Sources/App/"],
            }
        }
        self.assertEqual(SDLC.enforce_changed_files(paths, states), [])

    def test_unrelated_verified_bundle_does_not_cover_change(self) -> None:
        state_path = Path("docs/sdlc/changes/2026-08-25-test-change/state.json")
        paths = [
            "Resources/OpenType.entitlements",
            "docs/sdlc/changes/2026-08-25-test-change/verification.md",
        ]
        states = {
            state_path: {
                "status": "verified",
                "risk": "low",
                "governedPaths": ["Sources/App/"],
            }
        }
        errors = SDLC.enforce_changed_files(paths, states)
        self.assertTrue(any("do not cover" in error for error in errors))

    def test_release_workflow_requires_high_risk_bundle(self) -> None:
        state_path = Path("docs/sdlc/changes/2026-08-25-test-change/state.json")
        paths = [
            ".github/workflows/release.yml",
            "docs/sdlc/changes/2026-08-25-test-change/verification.md",
        ]
        states = {
            state_path: {
                "status": "verified",
                "risk": "medium",
                "governedPaths": [".github/workflows/"],
            }
        }
        errors = SDLC.enforce_changed_files(paths, states)
        self.assertTrue(any("insufficient risk" in error for error in errors))

    def test_ui_and_privacy_paths_have_documented_minimum_risk(self) -> None:
        self.assertEqual(SDLC.minimum_risk("Sources/UI/SettingsView.swift"), "medium")
        self.assertEqual(SDLC.minimum_risk("Sources/Speech/WhisperEngine.swift"), "medium")
        self.assertEqual(SDLC.minimum_risk("Sources/Screen/ScreenOCR.swift"), "high")
        self.assertEqual(SDLC.minimum_risk("Sources/LLM/RemoteLLMClient.swift"), "high")
        self.assertEqual(SDLC.minimum_risk("Sources/Config/AppSettings.swift"), "high")
        self.assertEqual(SDLC.minimum_risk("Sources/Hotkey/HotkeyManager.swift"), "high")
        self.assertEqual(SDLC.minimum_risk("Sources/Speech/AppleSpeechEngine.swift"), "high")
        self.assertEqual(SDLC.minimum_risk("Resources/Info.plist"), "high")

    def test_worktree_rename_keeps_governed_source_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "docs" / "research").mkdir(parents=True)
            source = root / "scripts" / "guard.sh"
            source.write_text("guard\n", encoding="utf-8")
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(
                ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "base"],
                cwd=root,
                check=True,
            )
            subprocess.run(
                ["git", "mv", "scripts/guard.sh", "docs/research/guard.md"],
                cwd=root,
                check=True,
            )
            paths = SDLC.changed_files(root, base=None, worktree=True)
            self.assertIn("scripts/guard.sh", paths)

    def test_base_diff_includes_deleted_governed_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Tests").mkdir()
            removed = root / "Tests" / "RemovedTests.swift"
            removed.write_text("test\n", encoding="utf-8")
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com"]
            subprocess.run(["git", *identity, "commit", "-qm", "base"], cwd=root, check=True)
            base = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
            ).stdout.strip()
            removed.unlink()
            subprocess.run(["git", "add", "-u"], cwd=root, check=True)
            subprocess.run(["git", *identity, "commit", "-qm", "delete"], cwd=root, check=True)
            paths = SDLC.changed_files(root, base=base, worktree=False)
            self.assertIn("Tests/RemovedTests.swift", paths)

    def test_push_diff_handles_divergent_history(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Tests").mkdir()
            removed = root / "Tests" / "RemovedTests.swift"
            removed.write_text("test\n", encoding="utf-8")
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com"]
            subprocess.run(["git", *identity, "commit", "-qm", "base"], cwd=root, check=True)
            base = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
            ).stdout.strip()
            subprocess.run(["git", "checkout", "--orphan", "rewrite", "-q"], cwd=root, check=True)
            removed.unlink()
            (root / "README.md").write_text("rewrite\n", encoding="utf-8")
            subprocess.run(["git", "add", "-A"], cwd=root, check=True)
            subprocess.run(["git", *identity, "commit", "-qm", "rewrite"], cwd=root, check=True)
            paths = SDLC.changed_files(root, base=base, worktree=False, two_dot=True)
            self.assertIn("Tests/RemovedTests.swift", paths)

    def test_research_only_change_uses_fast_path(self) -> None:
        paths = ["docs/research/finding.md"]
        self.assertEqual(SDLC.enforce_changed_files(paths, {}), [])

    def test_sdlc_policy_change_is_governed(self) -> None:
        errors = SDLC.enforce_changed_files(["docs/sdlc/README.md"], {})
        self.assertEqual(len(errors), 1)


if __name__ == "__main__":
    unittest.main()
