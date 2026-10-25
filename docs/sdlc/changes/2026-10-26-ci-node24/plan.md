# Plan: Upgrade the GitHub Actions runtime to Node 24

**Status:** approved
**Approved-by:** User, explicit approval in this conversation: 批准
**Approved-date:** 2026-10-26
**Upstream:** [spec.md](spec.md)

## Work items

- [x] Confirm branch `t3/upgrade-node`, its remote, and existing worktree changes.
  Preserve changes outside this bundle and the six workflows.
- [x] Recheck the selected action metadata against the approved
  [design](spec.md), including the pinned nested Pages upload action. Stop if
  runtime declarations or consumed interfaces have changed.
- [x] Apply the design's five version replacements to exactly twelve action
  references across the six workflows. Keep every other workflow line intact.
- [x] Review the workflow diff and run the local checks below. Run the repository
  checks and Swift tests sequentially because they share SwiftPM build state.
- [x] Record commands, exit codes, evidence, and any remaining limits in
  `verification.md`. Set its status to `pending approval` after validation.
- After verification approval, commit the reviewed change and perform the
  previously requested push. Verify the remote SHA, worktree status, and fresh
  CI state. Use the repository's PR flow and link the PR to this thread.

## Verification plan

- [x] Check that the workflow diff contains only the twelve approved `uses:`
  replacements. Confirm that existing action inputs and protected job settings
  remain intact.
- [x] Confirm that every selected JavaScript action, including the pinned nested
  Pages action, declares Node 24.
- [x] Run `actionlint -no-color -shellcheck=` on `pr.yml`, `pages.yml`,
  `manual-app-artifact.yml`, `nightly-release.yml`, `release.yml`, and
  `release-artifact.yml` under `.github/workflows/`.
- [x] Run `bash scripts/sdlc-checks.sh`.
- [x] Run `bash scripts/ci-basic-checks.sh`, including its release workflow
  contract checks.
- [x] Run `swift test`, with `--jobs 4` to limit compiler concurrency.
- [x] Run `git diff --check` and inspect the final diff before committing.
- After push, compare the remote branch SHA with the pushed local commit and
  record CI for that commit. Keep local validation, PR CI, Pages deployment,
  manual artifact delivery, and release results separate.

No new test harness or dependency is needed for these reference replacements.
The existing checks and remote workflows exercise the relevant contracts.

## Human gates

- Intent approved by the user on 2026-10-26.
- Design approved by the user on 2026-10-26.
- Plan approved by the user on 2026-10-26 before workflow edits or implementation
  validation.
- Verification approved by the user on 2026-10-26. The earlier `push` request
  supplies authorization for delivery.
- Merge, production release, and manual deployment remain outside this request.

## Rollback

Revert the action-reference updates if fresh CI identifies an incompatibility.
Restore only this change's references and preserve unrelated work. Reverting
does not restore Node 20 on GitHub's runners.
