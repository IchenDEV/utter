# Plan: Scheduled nightly releases from `main`

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** docs/sdlc/changes/2026-09-18-nightly-release-pipeline/spec.md

## Work items

- [x] Add `scripts/nightly-release-plan.sh`: stable-tag discovery (numeric
      ordering), branch-tip comparison, patch bump, validated output fields.
- [x] Add `scripts/tests/test_nightly_release_plan.sh`: fixture-repo coverage
      plus workflow-wiring assertions; wire it into `scripts/ci-basic-checks.sh`.
- [x] Extract the sign/verify/publish job into
      `.github/workflows/release-artifact.yml` (`workflow_call`) with
      `version`, `tag`, `create_tag`, `require_ancestor` inputs.
- [x] Rewrite `.github/workflows/release.yml` to keep its `validate` job and
      call the reusable workflow; keep the `v*` tag trigger unchanged.
- [x] Add `.github/workflows/nightly-release.yml`: cron `0 12 * * *` +
      `workflow_dispatch`, non-cancelling concurrency, `plan` ->
      `validate` -> reusable release with `create_tag: true`.
- [x] Update `scripts/tests/test_release_version.sh` to assert the shared
      guardrails against `release-artifact.yml`.
- [x] Add the `docs/sdlc/changes/2026-09-18-nightly-release-pipeline/` bundle.

## Verification plan

- [x] `bash scripts/tests/test_nightly_release_plan.sh`
- [x] `bash scripts/tests/test_release_version.sh` and `test_build_version.sh`
- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test` (regression: no app-code change)
- [ ] PR CI: Contract & Tests / Release-style App Build / SDLC Gate
- [ ] Post-merge: `workflow_dispatch` the nightly workflow and confirm the
      plan output/skip reason; first scheduled run is the production evidence.

## Human gates

- User confirms the two open assumptions in the intent: 20:00 Asia/Shanghai
  schedule and normal patch releases rather than `nightly-*` prereleases.
- Approving this bundle is the design/rollback review for a release change.
- The `production` environment approval on each real release remains human.
