# Verification: The "insertion unconfirmed" notice must be compact and leave on its own

**Status:** approved
**Approved-by:** User, answered the approval question in this conversation: approve this verification, including its four disclosed deviations and the unmeasured items, and authorize commit, push, PR, merge after all checks are green, the v0.0.62 tag and publication under release-runbook.md; stop and report on any red check
**Approved-date:** 2026-11-03
**Upstream:** [plan.md](plan.md)

Implemented on top of `origin/main` at `3748367` (v0.0.61 plus later merges).

## Acceptance criteria and evidence

| # | Criterion (from the intent) | Evidence | Result |
|---|---|---|---|
| 1 | `uncertain` HUD with the production message: icon, full message, Copy and Close on one row, height below 96 pt, light and dark, zh and en | `OverlayAlertLayoutTests.testUnconfirmedInsertionIsOneCompactRowInBothLanguages` (zh 46 pt, en 58 pt, `inline`); renders `evidence/after-uncertain-dark.png`, `after-uncertain-english-dark.png`, `after-uncertain-short-dark.png`; **real windows** over a white and a dark window: `evidence/real-window-white-uncertain-zh.png`, `real-window-dark-uncertain-zh.png`, `real-window-white-uncertain-en.png` (real `OverlayPanel`, `screencapture`) | Met |
| 2 | `.error` HUDs (models, permissions, clipboard-disabled) use the new layout with action button and unclipped message, zh and en | `testErrorsKeepTheirActionOnTheRowAndAreNotTallerThanThreeLines` (all inline, at most 58 pt); renders `after-models-dark.png`, `after-models-english-light.png`, `after-permissions-light.png`, `after-permissions-english-dark.png`, `after-clipboard-disabled-dark.png` | Met |
| 3 | After an `uncertain` session the overlay hides after the dwell; a newer session is not hidden by the old timer; `failed` is not auto-hidden; the 1.5 s path for done/copied is unchanged | `DesktopOverlayDwellTests` (7 tests, fake overlay, dwell shortened to 120 ms). Mutation check: with `autoDismisses` forced to false, 3 of these tests plus the unit test fail, so they do detect the regression. | Met |
| 4 | After auto-dismissal, a menu bar click while still `uncertain` shows the notice again and it leaves again | `testMenuBarReopensTheNoticeAndItLeavesAgain`, `testMenuBarDoesNotShowANoticeWhenNothingIsUnconfirmed` call `reshowUnconfirmedNotice()`, the method `togglePopover` now calls. The status-item click itself (`togglePopover` with a real button) is not driven by a test. | Met for the logic; click path by code reading only |
| 5 | Copy still copies; Close still hides | The view passes the same `onCopy` / `onDismiss` closures as before; `dismissOverlay` is exercised in `testErrorsThatNeedActionStayUntilClosed`. Clicking the new capsule button in a live window was **not** done. | Partly: wiring tested, live click not exercised |
| 6 | `keepsVisible`, `canCopy`, history, menu bar phase unchanged | `SessionPresentationTests` and `PresentationProjectionTests` pass; no file under `UtterMacServices`, `UtterSession`, `UtterData` changed (`git diff --stat` below) | Met |
| 7 | `sdlc-checks.sh`, `ci-basic-checks.sh`, `swift test` | See "Commands". | Met |

## Commands

```text
swift test                      -> exit 0, 631 tests, 26 skipped (opt-in integration tests), 0 failures   (evidence/tests-full-suite.txt)
bash scripts/sdlc-checks.sh     -> SDLC checks passed.
bash scripts/ci-basic-checks.sh -> Basic CI checks passed.
```

Changed files (production): `UtterContracts/SessionPresentation.swift` (+2),
`UtterPresentation/NativeDesktopHost.swift`, `UI/OverlayLayout.swift`, `UI/OverlayPanelContent.swift`,
`UI/OverlayPanel.swift` (+1 accessor), `UI/SelectionReviewMetrics.swift` (+1 enum case); new
`UI/OverlayAlertMetrics.swift` (146 lines) and `UI/OverlayAlertView.swift` (119 lines). No new strings.

## Deviations from the approved spec (for your decision)

1. **Title and detail instead of one message (D4).** The spec said one `.caption.weight(.medium)` message, three lines.
   The first render wrapped the Chinese message inside a phrase ("Utter 不会自/动再次写入"). The message is now split at
   its first sentence end into a title (medium, 92% white) and a quieter detail (regular, 66% white); one-sentence
   messages stay a single title. Total lines are still capped at three. Strings are unchanged. Covered by
   `testMessageSplitsIntoTitleAndDetailAtTheFirstSentence`.
2. **Darker surface for the notice (D4: "surface stays `OverlayPanelSurface`").** It is the same view with a new
   `tint` parameter (default 0.22, unchanged for every other HUD); the notice uses 0.6. Reason, measured on real
   windows over white (`screencapture`, pixel sampled): at 0.22 the panel is (129,129,129), the owner's grey, and the
   detail text has 2.63:1 contrast; at 0.6 it is (66,66,66) with 5.47:1 for the detail and 8.82:1 for the title.
   Over a dark window it looks like the other HUDs. 0.45 and 0.7 were also captured and rejected (too grey / too opaque).
3. **Test support.** `OverlayPanel.windowFrame` (read-only, used by the real-panel test) and `NativeDesktopHost
   .reshowUnconfirmedNotice()` (was inline in `togglePopover`).
4. **One existing assertion changed.** `PresentationProjectionTests.testCopyAndUncertainReceiptsCannotProjectAsInserted`
   asserted the old fixed height `96`; it now asserts the alert layout and interactivity, which is what the test is
   about. The rendering test now uses the production message (the old one rendered the short fallback, which is why
   it did not show what the owner saw).

## Not verified, and residual risk

- **Not run against the live app.** The installed Utter 0.0.61 is the owner's daily driver and shares the bundle id, so
  it was not stopped or replaced. The `uncertain` path in ChatGPT (4 of 5 in the history) and the 8 s dwell on a real
  desktop were not observed. Real-window evidence is a real `OverlayPanel` over real windows, not the app.
- **Hover does not pause the 8 s timer.** If the pointer is already on Copy when it fires, the notice disappears; the
  menu bar icon reopens it and the text is on the clipboard (paste path) or in History.
- **VoiceOver / switch control** users have 8 s; same recovery. Not mitigated by a setting.
- **Reduce Transparency / Increase Contrast** use the same surface code; not re-rendered.
- **The root cause is untouched.** About 11% of recent dictations still end `uncertain` and now show a notice that is
  smaller and leaves by itself, not one that never appears. Candidates for a separate, high-risk intent: distinguish
  "target exposes no readable value, so confirmation is impossible" from "value read back differs", and treat only
  the former quietly. That changes the output path, so it needs its own bundle and an independent verifier.

## Rollback

Revert the commit. The previous behavior is the persistent 96 pt card; no setting, data or history migrates.

## Evidence

`evidence/before-*.png` (origin/main, production message), `evidence/after-*.png` (offscreen renders of the real
views), `evidence/real-window-*.png` (real panel over real windows), `evidence/tests-full-suite.txt`.

## Approval record

Approved by the owner on 2026-11-03 (chat answer), together with authorization to push, open the PR, merge when every
check is green, and tag and publish v0.0.62 under `release-runbook.md`. The release evidence is recorded in the PR and
the release workflow run, not rewritten here.
