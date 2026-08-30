# Spec: Replace the Python SDLC validator with a strict shell gate

**Status:** approved
**Approved-by:** chenli
**Approved-date:** 2026-08-31
**Upstream:** [intent.md](intent.md)

## Design

- `scripts/sdlc-checks.sh` iterates `docs/sdlc/changes/*/` and enforces, per artifact (intent, spec, plan, verification, release optional):
  - `Status` values limited to `draft | pending approval | approved | rejected | blocked`;
  - no later stage `approved` before an earlier one;
  - `approved` requires non-placeholder `Approved-by` and `Approved-date`.
- Artifacts without a `Status` header are legacy merged bundles and are skipped.
- Status header fields added to all templates in `docs/sdlc/templates/`.
- `state.json` is removed; the artifact header is the single source of stage state.

## Safety and failure modes

- The gate fails closed on malformed status values and on approvals with missing approver/date.
- Loss of the governed-changed-paths check means CI no longer requires a changed verified bundle for specific paths; mitigation: `scripts/ci-basic-checks.sh`, `swift test`, and the release-style build still run on every PR, and AGENTS.md keeps the strict-approval contract.

## Test strategy

- Positive: gate passes on the current tree.
- Negative: a bundle with an out-of-order approval or missing approver must fail.

## Rollout and rollback

Single documentation/tooling commit; rollback by reverting it.
