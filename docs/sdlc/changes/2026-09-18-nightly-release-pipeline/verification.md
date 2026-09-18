# Verification: Scheduled nightly releases from `main`

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** docs/sdlc/changes/2026-09-18-nightly-release-pipeline/plan.md

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/tests/test_nightly_release_plan.sh` | Pass | "Nightly release plan tests passed." (first release 0.0.1 / no-op / patch bump 0.0.46 / rollover 0.1.9->0.1.10 / numeric ordering v0.0.10 > v0.0.9 / prerelease rejected / unknown branch + missing args fail / workflow wiring / shared-pipeline guardrails) |
| `bash scripts/tests/test_release_version.sh` | Pass | Guardrails re-asserted against `release-artifact.yml` |
| `bash scripts/tests/test_build_version.sh` | Pass | Unchanged |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| Workflow YAML parses | Pass | `release.yml` jobs `[validate, release]`, `release-artifact.yml` `[release]`, `nightly-release.yml` `[plan, validate, release]` |
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." |
| `swift test` (focused regression) | Pass | 396 passed / 8 skipped / 0 failures (no app-code change) |
| PR CI: Contract & Tests / Release-style App Build / SDLC Gate | Not run | Pending PR |

## Acceptance criteria

- Schedule + dispatch + non-cancelling concurrency — pass (workflow source,
  asserted by the shell test).
- No-op skip with a stated reason, and release jobs gated on `changed` — pass
  (shell test plus `if: needs.plan.outputs.changed == 'true'` assertions).
- Patch bump and validated version — pass (shell test; every emitted version is
  re-validated by `release-version.sh`).
- Signing/publish shared with the tag workflow, not copied — pass
  (`release.yml` and `nightly-release.yml` both call
  `release-artifact.yml`; guardrail greps moved there).
- Guardrails preserved: self-signed/Developer-ID modes, checksum verification,
  immutable-asset refusal, no ad-hoc fallback — pass (assertions in both shell
  tests).
- SDLC gate passes — pass locally; PR gate pending.
- Production publish evidence — deferred to the first gated run (not
  reproducible on a PR because `production` is tag-restricted).

## Residual risk

- The reusable workflow changes the release path for *both* entry points, so a
  defect would affect manual releases too. Mitigated by keeping the step bodies
  byte-identical in intent and by the guardrail assertions; owner: release
  maintainer.
- `create_tag` runs inside the `production`-gated job, so a nightly release
  still needs environment approval when that protection is active; an
  unapproved run blocks (no partial publish). Owner: repository admin.
- Scheduled workflows are disabled automatically after 60 days of repository
  inactivity and only run on the default branch; owner: release maintainer.
- Nightly runs will publish whatever is on `main` at 20:00 Asia/Shanghai. If a
  stricter staging window is wanted, a `nightly-*` prerelease variant is a small
  change (see intent open questions). Owner: user.
- `workflow_dispatch` of the nightly workflow publishes when there are
  unreleased commits; the runbook/PR description must say so. Owner: release
  maintainer.

## Decision

Ready for review. Human approval is recorded separately in the artifact
headers; the production release itself still requires the `production`
environment approval.
