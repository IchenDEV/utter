# Spec: Scheduled nightly releases from `main`

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** docs/sdlc/changes/2026-09-18-nightly-release-pipeline/intent.md

## Context

`release.yml` currently owns both the release candidate checks and the
signing/publish steps. It is triggered only by pushing a `v*` tag. The
`release` job runs in the protected `production` environment, imports
`APPLE_CERTIFICATE_P12`, verifies the built app's authority against the
configured identity, publishes a draft release, re-downloads the assets,
checks the SHA-256, and only then flips the release to published + latest.

Reusable workflows can consume `secrets: inherit`, `environment`, and
`permissions`, but the expression context of a reusable workflow's caller is
**not** available in the callee, and a `needs` value from the top-level
workflow cannot be passed as an input. A workflow also cannot create the tag
that triggered it, so the nightly entry point must create the tag itself from
inside the callee.

## Design

Three layers:

1. `scripts/nightly-release-plan.sh <repository> [branch=origin/main]`
   Read-only planner. Finds the highest stable `vMAJOR.MINOR.PATCH` tag (numeric
   ordering, prerelease/build tags ignored), resolves the branch tip, and:
   - no stable tag yet -> `changed=true`, `version=0.0.1`;
   - tip == tag commit -> `changed=false` + `reason=`;
   - otherwise -> `changed=true`, `version=<next patch>`, `latest_tag=`,
     `head_sha=`, `commit_count=`, `commit_summary=` (newest-first subjects).
   The emitted version is validated through `release-version.sh`, so the
   planner cannot propose a tag the release validator would reject.

2. `.github/workflows/release-artifact.yml` (reusable, `workflow_call`)
   Owns the entire sign/verify/publish pipeline, extracted verbatim from
   `release.yml`'s `release` job: credential check, certificate import with the
   OpenSSL 3 `-legacy` fallback, Metal toolchain, signed build, authority +
   `verify-release-artifact.sh`, Developer ID notarization when applicable,
   checksum, draft publish, download + checksum + byte compare, then
   `--draft=false --latest`. Inputs: `version`, `tag`, `create_tag`,
   `require_ancestor`. Job name stays `Sign, Verify & Publish` so release
   evidence and the test assertions keep matching.

3. Entry points
   - `release.yml` keeps its `validate` job (tag SemVer + main ancestry,
     repository checks, unit tests) and calls the reusable workflow.
   - `nightly-release.yml` adds a `plan` job (ubuntu, checkout with tags),
     a `validate` job gated on `changed == 'true'`, and calls the reusable
     workflow with `create_tag: true`.

### Tag creation (nightly)

Inside the reusable workflow, before building: reject an existing remote tag,
require `HEAD == origin/main` tip, create an annotated tag there, and push it.
Then `require_ancestor` is false (the tag was just created on the tip) so the
existing ancestry check is not duplicated.

## Safety and failure modes

- **Writes to `main`.** The only write is `git push` of a tag, and only from
  the `production`-gated `release` job. The commit must equal the fetched
  `origin/main` tip; an existing tag or a moved tip aborts before anything is
  pushed.
- **Concurrent runs.** `concurrency: group: nightly-release` with
  `cancel-in-progress: false`, so a scheduled run and a dispatch cannot build
  the same version, and an in-flight publish is never cancelled.
- **No-op nights.** When `changed=false` the validation and release jobs are
  skipped; `production` is never entered and no tag is created.
- **Secrets.** No new secrets; the reusable workflow uses `secrets: inherit`
  from callers and still runs in the `production` environment.
- **Failure containment.** Any signing, verification, or checksum failure
  aborts before or during the draft publish; the immutable-asset guard
  (`gh release view` check) prevents replacing a published release, and there
  is still no ad-hoc signing fallback.
- **Rejected alternatives.** Inlining the pipeline in `nightly-release.yml`
  (drift risk), calling `release.yml` via `workflow_dispatch` with an input
  (cannot gate on a tag that does not exist yet), and shelling out from a
  workflow to `git push` a signed tag (no signature infrastructure).

## Test strategy

- Local: `bash scripts/tests/test_nightly_release_plan.sh`, run from
  `scripts/ci-basic-checks.sh`. Fixture repos cover: first release, no-op,
  patch bump, `9 -> 10` rollover, numeric tag ordering, prerelease rejection,
  unknown branch, and missing arguments. The same test asserts the workflow
  wiring (schedule, dispatch, concurrency, `create_tag`, shared reusable
  workflow) and re-asserts the guardrails that previously lived in
  `test_release_version.sh`.
- Local: `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`,
  `swift test` (unchanged app code, so this is regression evidence).
- PR CI: Contract & Tests, Release-style App Build, SDLC Gate.
- Manual after merge: `workflow_dispatch` the nightly workflow and inspect the
  plan output/skip reason; the first real nightly is the production evidence.
  Actual publish cannot be exercised on a PR because the `production`
  environment is tag-restricted.

## Rollout and rollback

1. Merge this change through a PR (SDLC Gate green).
2. Optionally `workflow_dispatch` once to observe the decision without
   publishing (it will publish if `main` has unreleased commits — do this only
   when a release is acceptable).
3. Observe the first scheduled run at 12:00 UTC.
4. Rollback: disable the scheduled trigger (or revert `nightly-release.yml`
   and this bundle). The manual tag workflow is untouched and keeps working.
   Already published releases and pushed tags are immutable and stay.
