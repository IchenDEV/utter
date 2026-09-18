# Intent: Scheduled nightly releases from `main`

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** User request in IDE-4 ("优化发布流程，晚上8点如果有变更 自动构建 nightly 包，用 wf 打包 release（和现在流程反过来）")

## Problem

Releasing today requires a human to create and push a `vMAJOR.MINOR.PATCH` tag,
which then triggers `.github/workflows/release.yml`. Nothing is released until
someone remembers to tag, so `main` can accumulate verified fixes for weeks
(the last release, `v0.0.45`, shipped 14 days after the one before it) even
though every change already passed the PR gate.

The user wants the direction reversed for routine releases: a scheduled check
should decide whether `main` moved, and if it did, build, sign, verify, and
publish the next patch release without a manual tag.

## Outcome

- A scheduled workflow runs daily at 20:00 Asia/Shanghai (12:00 UTC).
- When `main` has no commits newer than the latest stable release tag, the run
  skips and states why in the logs and step summary.
- When `main` has new commits, the workflow creates the next patch tag and
  publishes a normal (non-prerelease) GitHub Release with `Utter-<version>.dmg`
  and its `.sha256`, using the same signing/verification/publish steps and the
  same secrets as the manual tag workflow.
- The manual tag-triggered workflow keeps working unchanged as a fallback.

## Scope

- Affected: GitHub Actions release automation, `main` tag creation policy,
  release notes format.
- In scope: `nightly-release.yml` (schedule + dispatch), a shared reusable
  artifact workflow, a change-detection/version-bump script plus shell tests,
  SDLC artifacts for this change.
- Non-goals: app/product behavior, signing identity, notarization credentials,
  the `production` environment protection rules, the DMG build script, and the
  manual tag workflow's trigger.

## Constraints

- High-risk lane: signing, release, production publish, and automation that can
  write tags to `main`.
- Never tag a commit that is not the current `origin/main` tip; never move,
  delete, or force-push a tag; never replace published release assets.
- Never fall back to ad-hoc signing when the configured identity cannot be
  imported or the artifact fails verification.
- Releases stay non-prerelease patch releases; the version must be valid per
  `scripts/release-version.sh`.
- The scheduled job must not overlap itself.

## Acceptance criteria

- `nightly-release.yml` declares `cron: "0 12 * * *"`, `workflow_dispatch`, and
  a concurrency group that does not cancel an in-progress publishing run.
- With no commits since the latest stable tag, the plan step reports
  `changed=false` with a reason and the release jobs do not run.
- With new commits, the plan step reports the next patch version, and the
  signing/publish steps are the same ones the tag workflow uses (shared
  reusable workflow, not a copy).
- `scripts/tests/test_nightly_release_plan.sh` covers change detection, patch
  bumping, version ordering, prerelease-tag rejection, invalid inputs, and the
  workflow wiring; it runs from `scripts/ci-basic-checks.sh`.
- A dry `workflow_dispatch` run on a branch/PR produces the plan output; the
  production path is human-gated through the `production` environment.
- SDLC gate passes for this bundle.

## Open questions

- Confirm the schedule time and timezone (assumed 20:00 Asia/Shanghai).
- Confirm routine nightly releases should be normal patch releases rather than
  `nightly-*` prereleases.
- Confirm whether nightly should also create a git tag on `main` (it does, so
  the release is reproducible and the shared pipeline's ancestry check holds).
