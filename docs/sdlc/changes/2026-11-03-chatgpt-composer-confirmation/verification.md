# Verification: Confirm a paste into an empty-looking web editor whose placeholder disappears

**Status:** approved
**Approved-by:** Owner, chat answer "批准" (2026-11-04 11:17 UTC+8), accepting the residual risk of the waived hardware run; merge of #144 and the v0.0.63 tag authorized
**Approved-date:** 2026-11-04
**Upstream:** [plan.md](plan.md)

The automated half is done. **The hardware matrix was not run**: the owner chose not to test and delegated the
judgement (see "Hardware verification"). This file proves the rule against the measured shapes, not a live ChatGPT
dictation. That is a stated, owner-accepted residual risk.

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

## Hardware verification (spec Batch 3) — NOT RUN, owner waived

The spec asked for a verifier who is not the implementer, on a release-style build of this branch, with the installed
Utter 0.0.62 replaced for the run.

| Case | Runs | Result |
|---|---|---|
| ChatGPT, empty composer | 10 | not run |
| ChatGPT, caret at end of existing text | 10 | not run |
| ChatGPT, caret in the middle | 5 | not run |
| Cursor, T3, Dia, TextEdit unchanged | 1 each | not run |
| Forced non-landing case still reports `uncertain` | 1 | not run |

Verifier: the implementing assistant. **Waivers:** the owner waived an independent verifier and allowed the installed
Utter 0.0.62 to be replaced for the run, with the owner re-granting permissions afterwards (chat answer "批准",
2026-11-03 23:28 UTC+8). Later the owner answered "你凭根据感觉来搞吧，不要我实测了" (2026-11-04 02:44 UTC+8): no
owner testing, judgement delegated. The verification stage itself still needs the owner's approval.

### Judgement in place of the run (assistant's, not evidence)

- The accepted value for the empty composer is the exact shape recorded from the owner's ChatGPT in
  `evidence/batch0-shapes.txt` (12 units before, the replacement alone after); the rule is pinned to those numbers by
  tests and four mutation kills, and it never accepts the original value, so an unchanged field still ends `uncertain`.
- Anything the rule does not recognise falls back to the old behaviour (`uncertain`), so a wrong guess costs a
  notice, not a wrongly reported insertion.
- Combined with the compatibility change (no merge conflicts), every test bundle except `OpenTypeTests` passes locally
  and an ad-hoc `0.0.63` app builds; this branch's CI passed on its own head.
- After release, the first ChatGPT dictation into an empty composer settles it: `inserted` instead of `uncertain`. If
  `uncertain` still appears, the new `Delivery unconfirmed shape:` log line records the numbers to fix it with.

## Rollback

Revert the change commits. The previous behavior is the unconfirmed notice on empty ChatGPT composers. The hidden
switch `deliveryWebEditorPasteDisabled` also disables the new rule.
