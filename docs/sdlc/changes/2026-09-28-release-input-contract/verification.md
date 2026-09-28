# Verification: Restore the release workflow input contract

**Status:** approved
**Approved-by:** chenli (explicit approval in this chat)
**Approved-date:** 2026-09-28
**Upstream:** docs/sdlc/changes/2026-09-28-release-input-contract/plan.md

## Change and acceptance evidence

The nightly adapter now emits separate numeric version and prefixed tag
outputs. The manual caller consumes its existing numeric resolver through a
job output. The shared pipeline only checks pre-existing tag ancestry when
`require_ancestor && !create_tag`; nightly creation still validates the main
tip and refuses an existing remote tag.

The new `scripts/tests/test_release_workflow_contract.sh` executes the actual
workflow shell blocks using temporary output files and disposable local Git
repositories. All remote push operations in those blocks are intercepted.

Before workflow edits, the new test failed nine assertions covering both
entry-point contracts and the new-tag ancestry condition. After repair it
passed, including the reported `0.0.47` / `v0.0.47` pair. The test also covers
first release, no-change output, malformed/missing/mismatched inputs, an
absent new tag, existing main tag, off-main tag, moved main tip, and conflicting
remote tag. Rejected paths never reach the push stub.

## Checks

| Check | Result |
| --- | --- |
| Release workflow contract regression before repair | Failed as expected: 9 assertions |
| Release workflow contract regression after repair | Passed |
| Existing release version and nightly planner suites | Passed |
| `bash scripts/sdlc-checks.sh` | Passed |
| `bash scripts/ci-basic-checks.sh` | Passed, including the new regression suite |
| `bash -n scripts/tests/test_release_workflow_contract.sh` | Passed |
| `git diff --check` | Passed |
| `swift test` | Passed: 793 XCTest cases, 18 skipped, 0 failures; 1 Swift Testing case passed |
| `bash scripts/build-app.sh --app-only --sign=-` | Passed; assembled app and release artifact verification passed |

## Independent review

A fresh-context, read-only verifier reviewed the approved intent/design/plan,
the workflow diff, and the executable regression coverage. It independently
reran all three release shell suites and `git diff --check`: all passed.
It reported no actionable findings and confirmed that production environment,
permissions, signing, notarization, and immutable-asset controls are retained.

The verifier did not run Swift/build checks or claim GitHub/production
acceptance. The push stub proves dispatch and pre-push rejection, not a real
concurrent remote tag race; the existing non-force push remains unchanged.

## Delivery boundary and residual risk

The implementation is based on main commit
`e3314bd649c0358a37d47087a7687af64213c056`, matching remote main at the
implementation check. PR mergeability and remote CI remain to be checked
after human verification approval and PR submission.

No production workflow was dispatched, release tag pushed, signing credential
accessed, or release published. Local tests do not prove GitHub expression
evaluation or protected-environment execution. The completed ad-hoc app build
is the PR-style packaging check, not release-signing or notarization evidence.
The 18 skipped XCTest cases require opt-in integration settings or local
models; they are not reported as executed. No application/UI behavior
changed, so microphone and real-window QA do not apply to this repair.

Rollback remains a scoped workflow/test revert. Already pushed release tags
and published assets must not be moved or replaced.
