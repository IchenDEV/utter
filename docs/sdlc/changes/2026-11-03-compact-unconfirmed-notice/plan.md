# Plan: The "insertion unconfirmed" notice must be compact and leave on its own

**Status:** approved
**Approved-by:** User, answered the approval question in this conversation: design A (compact, self-dismissing notice, 8 s), and approve intent, spec and plan together. PR, merge, tag and release remain separate decisions
**Approved-date:** 2026-11-03
**Upstream:** [spec.md](spec.md)

## Work items

| # | Item | Files | Check |
|---|---|---|---|
| A | `SessionPresentation.autoDismisses` (true only for `.uncertain`) | `Sources/UtterContracts/SessionPresentation.swift`, `Tests/UtterContractsTests/SessionPresentationTests.swift` | Unit test; existing expectations unchanged. |
| B | Host dwell: `uncertainDwell`, `scheduleHide(after:for:)`, `project` and `togglePopover` use it | `Sources/UtterPresentation/NativeDesktopHost.swift`, new `Tests/OpenTypeTests/DesktopOverlayDwellTests.swift` | Fake overlay: hides after dwell, newer session not hidden, `failed` not hidden, 1.5 s path unchanged, menu-bar reopen re-arms. |
| C | Alert layout: `OverlayLayout.Content.alert`, `OverlayAlertMetrics` (measurement), `OverlayAlertView` (row, capsule button style), `OverlayContentView` uses it for `.error/.uncertain`, old `recoveryControls` kept only for the review case | `Sources/UtterPresentation/UI/OverlayLayout.swift`, new `OverlayAlertMetrics.swift`, new `OverlayAlertView.swift`, `OverlayPanelContent.swift`, `Tests/OpenTypeTests/OverlayLayoutTests.swift` | Layout tests for zh/en/long text; files stay under 300 lines. |
| D | Render test uses the production message and adds English `uncertain`; real `OverlayPanel` frame test | `Tests/OpenTypeTests/PresentationRenderingTests.swift` | PNGs in `evidence/after-*.png`; visual review for clipping and alignment in light and dark, zh and en. |
| E | Repo checks and verification record | `verification.md` | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`, logs in `evidence/`. |
| F | PR, CI, then (only with the owner's authorization) merge, tag, release | GitHub | PR checks and `SDLC Gate` green; release per `release-runbook.md`. |

Order: A, B, C, D, E. Each is a small commit-sized step; run the focused tests after each.

## Verification plan

- **Automated:** the tests above, then the full suite and both scripts.
- **Visual:** before/after PNGs for `uncertain` (zh dark/light, en), models, permissions and clipboard-disabled.
  Compared against `evidence/before-*.png`.
- **Runtime:** the installed Utter 0.0.61 is the owner's daily driver and shares its bundle id, so it is not stopped or
  replaced to test. Real-window evidence comes from rendering the real SwiftUI views in real `NSWindow`s and from
  a real `OverlayPanel` frame test. Whether a dev build should also be run against the live app, and the
  `uncertain` path in ChatGPT, is the owner's call at verification time; absence is recorded as residual risk.
- **Not covered, recorded:** hover pause, VoiceOver timing, Reduce Transparency re-render.

## Stop conditions

- Delivery, history or receipt behavior changes in any test.
- Clipped or overlapping text in any render.
- A timer from an earlier session hides a later session's overlay.
- Any file would exceed 300 lines: split it.

## Release authorization (not implied by approving this plan)

Pushing the branch, opening the PR, merging, creating the `v0.0.62` tag and publishing are separate decisions. The
owner asked for a release after the change is done; this plan asks for that authorization again, once, together with
the verification review, so the decision is made with the evidence in hand. The release stops under the runbook's
stop conditions (red check, missing identity, mismatched artifact, existing release).
