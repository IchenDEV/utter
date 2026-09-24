# Verification: Restore nightly and tag-triggered release startup

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Workflow permission regression | Pass locally | `bash scripts/tests/test_nightly_release_plan.sh` failed on the old `release.yml` permission ceiling, then passed after both callers granted job-level write access. |
| `bash scripts/sdlc-checks.sh` | Pass locally | Stage order and approval fields passed. |
| `bash scripts/ci-basic-checks.sh` | Pass locally | Basic CI checks passed, including the workflow wiring test. |
| `swift test --scratch-path /tmp/utter-silent-insertion-build` | Pass locally | 793 XCTest cases, 18 skipped, zero failures; one Swift Testing case passed. |
| GitHub PR checks and mergeability | Pending | — |
| Real Nightly startup | Pending | Requires merge to `main` and an authorized run. |

## Acceptance criteria

- Both release entry points grant the required scope to the shared workflow — pass in source and local regression check.
- Planning and validation remain read-only — pass in source; workflow-level defaults remain `contents: read`.
- A regression check rejects the prior mismatch — pass; observed red before the fix and green afterward.
- A real Nightly run reaches `plan` — pending post-merge observation.

## Residual risk

GitHub validates reusable workflow composition only on a real run of the
updated workflow. Local checks cannot establish that the next scheduled run
will reach `plan`. Protected release signing and publication are also outside
local and PR validation.

## Decision

The local fix is ready for PR checks and independent review. The first real
Nightly startup after merge remains the production acceptance check; protected
release approval is separate.
