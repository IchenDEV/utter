# Plan: Restore nightly and tag-triggered release startup

**Status:** approved
**Approved-by:** User (explicit approval of all stages in the task)
**Approved-date:** 2026-09-24
**Upstream:** [spec.md](spec.md)

## Work items

- [x] Add a regression assertion to the existing workflow wiring test and
  observe it fail on the current callers.
- [x] Grant `contents: write` on the `release` calling job in both entry-point
  workflows, leaving top-level permissions read-only.
- [ ] Run local checks, review the exact diff, and create a conflict-free PR.

## Verification plan

- [x] `bash scripts/tests/test_nightly_release_plan.sh` red before the fix and
  green after it.
- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test --scratch-path /tmp/utter-silent-insertion-build`
- [ ] GitHub PR checks and mergeability; actual Nightly startup after merge is
  a separate protected release observation.

## Human gates

Independent high-risk review, PR approval, and protected production approval
remain required. The user approved the intent, design, and implementation
stages in this task; verification evidence will be recorded after the checks.
