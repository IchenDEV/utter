# Plan: Restore the release workflow input contract

**Status:** approved
**Approved-by:** chenli (explicit approval in this chat)
**Approved-date:** 2026-09-28
**Upstream:** docs/sdlc/changes/2026-09-28-release-input-contract/spec.md

## Work items

- [x] Create `codex/fix-release-input-contract` in this checkout after checking
  the current branch, remote main, and unrelated changes. Preserve the approved
  change bundle and keep implementation limited to this release contract.
- [x] Add a focused executable workflow contract test under `scripts/tests/`
  and call it from `scripts/ci-basic-checks.sh`. Reuse existing planner and
  version-validator fixtures where practical. Extract the actual named shell
  blocks with bounded shell tooling and reject missing blocks. Check the
  relevant step/job/caller references explicitly.
- [x] Demonstrate failures on the original nightly version/tag output, manual
  version input, and new-tag ancestry condition before fixing the workflows.
  Keep failure evidence in `verification.md`.
- [x] Update `.github/workflows/nightly-release.yml` to preserve the numeric
  version and emit the corresponding prefixed tag as separate outputs.
- [x] Update `.github/workflows/release.yml` to expose and consume the existing
  resolved numeric version through the validation job output.
- [x] Update `.github/workflows/release-artifact.yml` so existing-tag ancestry
  validation runs only for `require_ancestor && !create_tag`. Retain the
  nightly main-tip and existing-tag checks. Correct the obsolete header
  comment without modifying signing or publication behavior.
- [x] Complete local verification and a fresh-context independent read-only
  review. Resolve findings and repeat only affected checks. Record outcomes
  and evidence gaps in `verification.md`, then request human verification
  approval before proceeding to the PR/release gate.

## Verification plan

- [x] Execute both entry points' version-resolution/output shell blocks and
  pass their resulting values into the shared version/tag validator. Assert
  the reported candidate becomes `0.0.47` / `v0.0.47` in both paths.
- [x] Cover first release, no-change skip, missing/malformed tags, and a
  mismatched numeric version. Retain existing planner coverage for patch
  rollover, tag ordering, and invalid repository/branch inputs.
- [x] Use disposable local Git fixtures to exercise an absent new tag,
  existing main tag, off-main tag, moved main tip, and conflicting remote tag.
  Stub push; rejected paths must never invoke it. Verify the new-tag path
  reaches the push stub only after the existing main-tip checks succeed.
- [x] Run `bash scripts/tests/test_release_version.sh`,
  `bash scripts/tests/test_nightly_release_plan.sh`, and the new contract test.
- [x] Run `bash scripts/sdlc-checks.sh` and `bash scripts/ci-basic-checks.sh`.
- [x] Run `swift test`.
- [x] Run `bash scripts/build-app.sh --app-only --sign=-`, matching the PR
  packaging check. This explicitly selected ad-hoc test build is local build
  evidence only; it is not a fallback for failed configured release signing.
- [x] Have the independent verifier inspect the accepted artifacts and diff,
  rerun the contract tests, and report correctness findings or evidence gaps.
- [x] Check diff whitespace and unresolved conflict markers. Remote main still
  matches the implementation base at the final local check.
- [ ] After verification approval, refresh remote main, resolve any integration
  conflicts, submit and attach the PR, and confirm GitHub mergeability and all
  required checks, including `SDLC Gate`.

No app UI or permission behavior changes are planned, so real-window and
microphone QA are not applicable. No local command dispatches a production
workflow, pushes a release tag, imports release credentials, or publishes an
artifact. Fixture results, local build results, remote CI, and production
release acceptance remain separate evidence.

## Human gates

Intent and design were explicitly approved by chenli on 2026-09-28. The user approved this plan on the same date; implementation is authorized. Verification then requires
human acceptance, followed by PR approval and the existing protected production
approval. The independent verifier cannot provide those human approvals.

## Rollback

Revert the scoped workflow/test commit if needed, preserving already-created
tags and published assets. Stop an in-progress release before changing its
automation. Do not move tags, overwrite assets, or weaken signing to recover.
