# Verification: Confirm a paste into an empty-looking web editor whose placeholder disappears

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

This file is a draft on purpose: the automated half is done, the hardware half is not. Do not read it as release
evidence until the hardware section below is filled in and the owner approves this stage.

## What was implemented (plan items A–E)

| Item | Result |
|---|---|
| A. `DeliveryExpectation.acceptedDocuments` | Done. The primary expected document is kept; for an empty-looking web content editor at range `(0, 0)` with a non-empty replacement, the replacement alone is a second accepted value. The original document is filtered out of the set, so an unchanged field is never accepted. The lone-`"\n"` rule is unchanged. |
| B. `DeliveryTextObservation` | Done. `observe(accepting:)` takes the set, polls as before (25 ms, 3 s) and returns the last readable value; `confirm` is a thin wrapper with the old signature. |
| C. `NativeDeliveryTarget` | Done. `confirm` and `insertionAnchor` use the accepted set; no new write path. |
| D. Counts-only diagnostic (D5) | Done. On a timeout `DeliveryShapeDiagnostic.summary` produces numbers and flags only, logged once as `Delivery unconfirmed shape: …` when the receipt is `uncertain`. |
| E. Mutation checks | Done, see below. |

## Automated evidence

- `swift test` on this branch: 631 tests, 26 skipped, 0 failures (second full run).
- First full run had 1 failure in `VoiceEditingNativeE2EPresentationTests.testRealSession…NativePointerRestores…`, a
  real-window test that clicks with a real pointer and asserts the frontmost application is unchanged at the end. At
  the end of that run another app (Feishu) was frontmost instead of the one that started it. The same test passed on
  the base commit without these changes, then passed twice on this branch, and the full suite then passed. This is
  recorded as environmental interference with a real-pointer test, not proven as such; the cause was not isolated.
- `bash scripts/ci-basic-checks.sh`: passed. `bash scripts/sdlc-checks.sh`: passed.
- Mutation checks, each run with `swift test --filter UtterMacServicesTests.DeliveryExpectationTests` and restored
  afterwards (the restored suite passes):

| Mutation | Suite result | Failing tests point at |
|---|---|---|
| Never add the replacement-only candidate | failed | the measured empty-composer shape and the draft-with-line-feed case |
| Drop the `(0, 0)` guard | failed | the "no extra candidate away from the start" cases |
| Drop the "never accept the original" filter | failed | the unchanged-field case and the delete case (an empty replacement would otherwise accept the original) |
| Drop the web-content-editor guard | failed | the native-editor case |

## Not covered by unit tests

- The AX-bound wiring in `NativeDeliveryTarget` (reading the live field, anchoring a restore) has no unit test: it
  needs a real focused element. The pure rule, the observation loop and the diagnostic are covered; the wiring is
  covered only by the hardware matrix below.
- Multi-paragraph text in ChatGPT, ChatGPT in a browser tab, and the second cause of `uncertain` (T3 with text before
  the caret). The diagnostic is there to measure the latter; no fix is claimed.

## Hardware verification (spec Batch 3) — NOT DONE

Required before release, by a verifier who is not the implementer, on a release-style build of this branch, which needs
the installed Utter 0.0.62 to be stopped or replaced for the run (the owner's decision):

| Case | Runs | Result |
|---|---|---|
| ChatGPT, empty composer | 10 | not run |
| ChatGPT, caret at end of existing text | 10 | not run |
| ChatGPT, caret in the middle | 5 | not run |
| Cursor, T3, Dia, TextEdit unchanged | 1 each | not run |
| Forced non-landing case still reports `uncertain` | 1 | not run |

Independent verifier: not assigned. If the owner waives independence, the waiver and its date go here.

## Rollback

Revert the change commits. The previous behavior is the unconfirmed notice on empty ChatGPT composers. The hidden
switch `deliveryWebEditorPasteDisabled` also disables the new rule.
