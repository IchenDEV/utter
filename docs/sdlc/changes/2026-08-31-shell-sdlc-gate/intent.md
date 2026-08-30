# Intent: Replace the Python SDLC validator with a strict shell gate

**Status:** approved
**Approved-by:** chenli
**Approved-date:** 2026-08-31

## Problem

The SDLC validator stack (`scripts/sdlc.py`, `scripts/sdlc_policy.py`, `scripts/tests/test_sdlc.py`, per-bundle `state.json`) is Python-based and duplicates the strict per-stage approval model the maintainer wants enforced. Stage approval should live in the artifacts themselves, checked by shell only.

## Outcome

- Stage order and approval fields are enforced by `scripts/sdlc-checks.sh` (pure bash) in CI and locally.
- No Python in the SDLC toolchain.

## Constraints

- Historical bundles merged before the gate keep their recorded evidence as-is (including past `sdlc.py` runs) and are grandfathered by the checks.
- The governed-changed-paths feature of `sdlc.py` is not reimplemented in shell; residual risk is recorded in verification.

## Acceptance criteria

- `scripts/sdlc.py`, `scripts/sdlc_policy.py`, `scripts/tests/test_sdlc.py` and all `state.json` files are removed.
- `bash scripts/sdlc-checks.sh` passes and rejects later-stage approvals before earlier ones.
- No `sdlc.py` references remain in AGENTS.md, READMEs, docs/sdlc prose, CI workflows, or scripts (historical bundle evidence excepted).
