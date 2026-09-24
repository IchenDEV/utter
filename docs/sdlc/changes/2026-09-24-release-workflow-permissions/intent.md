# Intent: Restore nightly and tag-triggered release startup

**Status:** approved
**Approved-by:** User (explicit approval of all stages in the task)
**Approved-date:** 2026-09-24
**Upstream:** [Nightly release pipeline](../2026-09-18-nightly-release-pipeline/intent.md) and [Nightly run #35888630166](https://github.com/IchenDEV/utter/actions/runs/35888630166)

## Problem

Six scheduled Nightly Release runs since 2026-09-18 ended with
`startup_failure` before any job ran. GitHub's annotation on run #35888630166
identifies the exact conflict: the reusable `release-artifact.yml` job requests
`contents: write`, while its `nightly-release.yml` caller allows only
`contents: read`. The tag-triggered `release.yml` has the same caller permission
and therefore shares the defect, although its most recent successful run
predates the reusable workflow change.

## Outcome

Both release entry points pass GitHub's reusable-workflow permission check.
Planning and validation remain read-only. The reusable release job can create
an immutable tag and publish the verified artifact only through the existing
`production` environment gate.

## Scope

- Change the `release` caller job in `nightly-release.yml` and `release.yml` to
  grant the `contents: write` scope already required by their shared release
  workflow.
- Extend the existing workflow wiring test to reject this specific permission
  mismatch before another scheduled run.
- Preserve the schedule, version planner, signing requirements, artifact
  verification, production protection, and shared release implementation.

## Constraints

- High-risk release/permission change: require reviewed design and plan,
  independent verification, PR approval, and protected production approval.
- Do not grant write access to planning or validation jobs.
- Do not create a tag or publish a release during local or PR verification.
- Keep the fix on an isolated branch, separate from the voice-input PR.

## Acceptance criteria

- A deterministic local check fails against the current caller permission
  mismatch and passes after both callers grant `contents: write` on their
  reusable-workflow call jobs.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and
  `swift test` pass on the fix branch.
- GitHub accepts a run of the updated Nightly workflow and starts its `plan`
  job; the release job remains subject to the existing `production` gate.
- The tag-triggered caller is covered by the same static regression check.

## Open questions

None. GitHub's startup annotation identifies the mismatch and the intended
write scope is already present in the reusable release job.
