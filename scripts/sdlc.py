#!/usr/bin/env python3
"""Validate Utter's artifact-driven SDLC contract without third-party packages."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from sdlc_policy import REQUIRED_HEADINGS, RISKS, STATUSES, is_governed_path, minimum_risk

ID_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*$")
PLACEHOLDER_PATTERN = re.compile(r"\{\{[^}]+\}\}")


def required_artifacts(status: str, risk: str) -> set[str]:
    status_index = STATUSES.index(status)
    required = {"intent"}
    if risk in {"medium", "high"} and status_index >= STATUSES.index("designed"):
        required.add("spec")
    if status_index >= STATUSES.index("planned"):
        required.add("plan")
    if status_index >= STATUSES.index("verified"):
        required.add("verification")
    return required


def path_is_in_scope(path: str, scope: str) -> bool:
    return path.startswith(scope) if scope.endswith("/") else path == scope


def load_state(state_path: Path, errors: list[str]) -> dict | None:
    try:
        value = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        errors.append(f"{state_path}: invalid JSON: {error}")
        return None
    if not isinstance(value, dict):
        errors.append(f"{state_path}: top-level value must be an object")
        return None
    return value


def validate_artifact(
    bundle_dir: Path, artifact: str, relative_path: object, errors: list[str]
) -> None:
    if not isinstance(relative_path, str) or not relative_path:
        errors.append(f"{bundle_dir}: artifact '{artifact}' needs a relative path")
        return
    relative = Path(relative_path)
    if relative.is_absolute() or ".." in relative.parts:
        errors.append(f"{bundle_dir}: artifact '{artifact}' must use a safe relative path")
        return
    artifact_path = bundle_dir / relative
    try:
        artifact_path.resolve().relative_to(bundle_dir.resolve())
    except ValueError:
        errors.append(f"{bundle_dir}: artifact '{artifact}' escapes its bundle")
        return
    current = bundle_dir
    for part in relative.parts:
        current /= part
        if current.is_symlink():
            errors.append(f"{artifact_path}: artifact paths may not contain symlinks")
            return
    if not artifact_path.is_file():
        errors.append(f"{artifact_path}: required artifact is missing")
        return
    text = artifact_path.read_text(encoding="utf-8")
    for heading in REQUIRED_HEADINGS[artifact]:
        if heading not in text:
            errors.append(f"{artifact_path}: missing heading '{heading}'")
    if PLACEHOLDER_PATTERN.search(text):
        errors.append(f"{artifact_path}: contains an unfilled template placeholder")


def validate_bundle(state_path: Path) -> tuple[dict | None, list[str]]:
    errors: list[str] = []
    state = load_state(state_path, errors)
    if state is None:
        return None, errors

    bundle_dir = state_path.parent
    bundle_id = state.get("id")
    if bundle_id != bundle_dir.name or not isinstance(bundle_id, str) or not ID_PATTERN.match(bundle_id):
        errors.append(f"{state_path}: id must match the yyyy-mm-dd-slug directory")
    if state.get("schemaVersion") != 1:
        errors.append(f"{state_path}: schemaVersion must be 1")
    if not isinstance(state.get("title"), str) or not state["title"].strip():
        errors.append(f"{state_path}: title must be non-empty")

    risk = state.get("risk")
    status = state.get("status")
    if risk not in RISKS:
        errors.append(f"{state_path}: risk must be one of {', '.join(RISKS)}")
    if status not in STATUSES:
        errors.append(f"{state_path}: status must be one of {', '.join(STATUSES)}")

    owners = state.get("owners")
    if not isinstance(owners, list) or not owners or not all(
        isinstance(owner, str) and owner.strip() for owner in owners
    ):
        errors.append(f"{state_path}: owners must be a non-empty string array")
    criteria = state.get("acceptanceCriteria")
    if not isinstance(criteria, list) or not criteria or not all(
        isinstance(criterion, str) and criterion.strip() for criterion in criteria
    ):
        errors.append(f"{state_path}: acceptanceCriteria must be a non-empty string array")
    governed_paths = state.get("governedPaths")
    if not isinstance(governed_paths, list) or not governed_paths or not all(
        isinstance(path, str)
        and path.strip()
        and not path.startswith(("/", "../"))
        and "/../" not in path
        and path not in {".", "./"}
        for path in governed_paths
    ):
        errors.append(f"{state_path}: governedPaths must contain safe repository-relative paths")

    artifacts = state.get("artifacts")
    if not isinstance(artifacts, dict):
        errors.append(f"{state_path}: artifacts must be an object")
        return state, errors
    if risk in RISKS and status in STATUSES:
        required = required_artifacts(status, risk)
        required_paths = [artifacts.get(artifact) for artifact in required]
        canonical_paths = [
            (state_path.parent / path).resolve()
            for path in required_paths
            if isinstance(path, str)
            and not Path(path).is_absolute()
            and ".." not in Path(path).parts
        ]
        if len(canonical_paths) != len(set(canonical_paths)):
            errors.append(f"{state_path}: required artifacts must use distinct files")
        for artifact in required:
            validate_artifact(bundle_dir, artifact, artifacts.get(artifact), errors)
    return state, errors


def validate_repository(root: Path) -> tuple[dict[Path, dict], list[str]]:
    states: dict[Path, dict] = {}
    errors: list[str] = []
    changes_root = root / "docs" / "sdlc" / "changes"
    if not changes_root.exists():
        return states, errors
    for state_path in sorted(changes_root.glob("*/state.json")):
        state, bundle_errors = validate_bundle(state_path)
        errors.extend(bundle_errors)
        if state is not None:
            states[state_path.relative_to(root)] = state
    orphan_dirs = sorted(path for path in changes_root.iterdir() if path.is_dir() and not (path / "state.json").is_file())
    errors.extend(f"{path}: change bundle is missing state.json" for path in orphan_dirs)
    return states, errors


def changed_files(
    root: Path, base: str | None, worktree: bool, two_dot: bool = False
) -> list[str]:
    commands: list[list[str]] = []
    if base:
        revision_range = f"{base}..HEAD" if two_dot else f"{base}...HEAD"
        commands.append(
            ["git", "diff", "--no-renames", "--name-only", "--diff-filter=ACMDT", revision_range]
        )
    elif worktree:
        commands.extend(
            (
                ["git", "diff", "--no-renames", "--name-only", "--diff-filter=ACMDT", "HEAD"],
                ["git", "ls-files", "--others", "--exclude-standard"],
            )
        )
    else:
        return []
    paths: set[str] = set()
    for command in commands:
        result = subprocess.run(command, cwd=root, check=True, capture_output=True, text=True)
        paths.update(line for line in result.stdout.splitlines() if line)
    return sorted(paths)


def enforce_changed_files(paths: list[str], states: dict[Path, dict]) -> list[str]:
    governed = [path for path in paths if is_governed_path(path)]
    if not governed:
        return []
    changed_bundle_dirs = {
        Path(*Path(path).parts[:4])
        for path in paths
        if len(Path(path).parts) >= 5
        and Path(path).parts[:3] == ("docs", "sdlc", "changes")
    }
    changed_states = {
        path: state
        for path, state in states.items()
        if path.parent in changed_bundle_dirs
    }
    if not changed_states:
        preview = ", ".join(governed[:5])
        return [f"governed changes require a changed SDLC bundle; governed paths: {preview}"]
    verified_index = STATUSES.index("verified")
    verified_states = [
        state
        for state in changed_states.values()
        if state.get("status") in STATUSES
        and STATUSES.index(state["status"]) >= verified_index
    ]
    if not verified_states:
        return ["at least one changed SDLC bundle must have status verified or later"]
    covering_states = {
        path: [
            state
            for state in verified_states
            if any(
                path_is_in_scope(path, scope)
                for scope in state.get("governedPaths", [])
                if isinstance(scope, str)
            )
        ]
        for path in governed
    }
    uncovered = [path for path, covering in covering_states.items() if not covering]
    if uncovered:
        preview = ", ".join(uncovered[:5])
        return [f"verified SDLC bundles do not cover governed paths: {preview}"]
    insufficient = [
        path
        for path, covering in covering_states.items()
        if not any(
            state.get("risk") in RISKS
            and RISKS.index(state["risk"]) >= RISKS.index(minimum_risk(path))
            for state in covering
        )
    ]
    if insufficient:
        preview = ", ".join(
            f"{path} (requires {minimum_risk(path)})" for path in insufficient[:5]
        )
        return [f"verified SDLC bundles have insufficient risk classification: {preview}"]
    return []


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate",), nargs="?", default="validate")
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--base", help="compare HEAD with this Git base")
    source.add_argument("--push-base", help="compare HEAD directly with the previous push SHA")
    source.add_argument("--worktree", action="store_true", help="check staged, unstaged, and untracked files")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parent.parent
    states, errors = validate_repository(root)
    try:
        paths = changed_files(root, args.base or args.push_base, args.worktree, bool(args.push_base))
    except subprocess.CalledProcessError as error:
        print(error.stderr, file=sys.stderr)
        return error.returncode
    errors.extend(enforce_changed_files(paths, states))
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    suffix = f"; checked {len(paths)} changed paths" if paths else ""
    print(f"SDLC validation passed ({len(states)} change bundles{suffix}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
