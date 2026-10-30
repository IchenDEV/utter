# Verification: Desktop Copy and Apply-replacement buttons must start a session

**Status:** approved            # draft | pending approval | approved | rejected | blocked
**Approved-by:** User, answered the approval question in this conversation: approve verification, commit, and open a PR
**Approved-date:** 2026-10-30
**Upstream:** [plan](plan.md)

## Change under verification

One condition in `Sources/UtterSession/SessionDriver.swift` (`admit`): the
`.local` binding for an `.unselected` intent now applies only when
`intent.operation == .input`. Tests added: `SessionDriverInputBindingTests`
(driver level) and `DesktopActionStartTests` (real `NativeDesktopHost` +
production factory); `installPending` moved into a shared fixture extension.

## Evidence

| Check | Result | Evidence |
|---|---|---|
| New tests fail before the fix | Pass: 4 of 5 fail on `0e0f3c1` (the host swallows `invalidSessionState`, so the tests see "no execution started"); the whitespace case passes both ways by design | [tests-before-fix.txt](evidence/tests-before-fix.txt) |
| New tests pass after the fix | Pass (5 of 5) | [tests-after-fix.txt](evidence/tests-after-fix.txt) |
| `swift test` | Pass: 618 tests, 26 skipped (pre-existing skips), 0 failures | `/tmp/test-full.log` (not committed; rerun to reproduce) |
| `bash scripts/ci-basic-checks.sh` | Pass: "Basic CI checks passed." | `/tmp/ci-basic.log` (not committed) |
| `bash scripts/sdlc-checks.sh` | Pass: "SDLC checks passed." | rerun at 2026-10-30 15:5x |
| Real window, dev build, Settings -> History Copy | Pass | [real-window-history-copy.txt](evidence/real-window-history-copy.txt) |
| Release-style build | Not run (plan: no packaging, dependency, or resource change) | — |

## Acceptance criteria

- Copy intent with `input: .unselected` on a real driver and the production
  factory ends `copied`, exact pasteboard text, no history or anchor change —
  pass (`testDesktopCopyStartsAndCopiesTheExactTextWithoutHistoryOrAnchorChange`;
  failed before the fix).
- Apply-replacement with `input: .unselected` behaves like the `.local` case —
  pass (`testDesktopApplyReplacementStartsAndReplacesTheRememberedInsertion`,
  `testDesktopApplyReplacementAfterExpiryCopiesInsteadOfReplacing`).
- Host hands the execution service the intents the tests use — pass, by
  construction: the tests call the real `host.copy` / `host.applyReplacement`
  instead of building intents by hand.
- Whitespace-only copy refuses to start; dictation with `.unselected` still
  binds `.local`; `.restoreSelectionEdit` unchanged — pass
  (`testDesktopCopyOfWhitespaceStartsNothing`, the driver test's
  `(.input, [.local])` case, and the existing restore tests in the full run).
- Dev build: Copy changes the pasteboard and leaves no `Desktop action could not
  start` entry — **partial**. Verified for the History row Copy button only.
  Overlay Copy, the three menu bar popover copy buttons, the History context
  menu, and the menu bar "replace with formatted text" button were not clicked
  in a real window. They share `NativeDesktopHost.copy` / `applyReplacement`,
  which are covered by the host tests.
- `sdlc-checks`, `ci-basic-checks`, `swift test` — pass.

## Residual risk

- Installed Utter 0.0.60 stays broken until a release containing this change
  ships. Owner: user (release is a separate human gate; intent open question 2).
- Real-window coverage is one of six call sites (see above). Risk is low because
  all call sites funnel into the same two host methods and the same driver
  path; owner: reviewer decides whether to click the remaining ones before merge.
- The dictation that failed at 15:15 is still in History marked "not written";
  it can be copied with the dev build, not with 0.0.60.
- Merging and releasing remain separate human gates; this approval covers committing and opening the PR only.

## Decision

Ready for review. Human approval is recorded separately.
