# Spec: Restore nightly and tag-triggered release startup

**Status:** approved
**Approved-by:** User (explicit approval of all stages in the task)
**Approved-date:** 2026-09-24
**Upstream:** [intent.md](intent.md)

## Context

GitHub rejects Nightly run #35888630166 at workflow composition, before any
job is created. Its annotation names `nightly-release.yml` line 107 and the
nested `release-artifact.yml` job: the caller allows `contents: read` while the
called job requests `contents: write`. `release.yml` calls the same reusable
workflow with the same read-only ceiling. The reusable job needs write access
to push an immutable tag for Nightly and publish release assets for either
entry point.

## Design

Add `permissions: { contents: write }` to the `release` calling job in each
entry-point workflow. Keep their top-level `contents: read` permissions so
`plan` and `validate` remain read-only. Keep the reusable workflow's job-level
write requirement as the one source of the publishing job's permission need.

Add one shared shell regression assertion to the existing release workflow
wiring test. It checks that both calling jobs grant the write scope required by
the reusable job and that each entry point still defaults to read-only. The
test has no GitHub credentials and creates no release.

## Safety and failure modes

- Write scope applies only to release calls, which already depend on successful
  validation and use the `production` environment in the reusable job.
- The fix does not change tag immutability, `main` tip checks, signing,
  notarization, artifact verification, or release asset replacement guards.
- GitHub repository or environment policy can still block a protected release;
  that is a separate runtime condition to report from a real run.
- Roll back by reverting the two caller permission additions and the test,
  which restores the prior startup failure without moving any tag or asset.

## Test strategy

Run the existing workflow wiring test before and after the YAML fix, then the
SDLC/basic checks and Swift tests. Inspect the PR's GitHub checks and
mergeability. After protected merge, a Nightly run must reach `plan`; no local
or PR check should create a tag or publish an artifact.

## Rollout and rollback

Submit as an isolated PR against `main`. An independent reviewer checks the
permission boundary and production protection before merge. Observe the first
scheduled run after merge. If it fails beyond startup, inspect its actual job
logs before changing signing or publication behavior.
