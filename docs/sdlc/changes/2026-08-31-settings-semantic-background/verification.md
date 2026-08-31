# Verification: Match the macOS settings background hierarchy

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Source inspection | Pass | Both shared settings paints now use AppKit `underPageBackgroundColor`; no fixed RGB or new material layer was added. |
| Real-window dark inspection | Pass | The built 760 by 680 window was opened through the actual AppKit/SwiftUI settings path; Activity and the ANE model pane use the lighter page surface while grouped sections, warning copy, switches, and labels remain legible. |
| `swift test` | Pass | 592 XCTest cases passed, 10 environment-gated cases skipped, and the Swift Testing model-upgrade test passed. |
| `bash scripts/sdlc-checks.sh` | Pass | The strict shell gate checked all 12 change bundles after merging current `main`; this intent remains pending human approval and later stages remain draft. |
| `bash scripts/ci-basic-checks.sh` | Pass | Package, shell SDLC gate, plist/localization parity, identifiers, vocabulary, resources, conflict markers, secrets, and symlink checks passed after conflict resolution. |
| Final `bash scripts/build-app.sh` | Pass | Final no-hook app and DMG rebuilt; app and mounted-DMG signatures and DMG checksum passed. |
| `git diff --check` | Pass | No whitespace errors after final evidence updates. |

## Acceptance criteria

- Shared semantic under-page background — pass in both shared source seams.
- Dark real-window page hierarchy and contrast — pass on Activity and ANE model
  content without layout changes.
- Regression and release-style checks — full tests, basic CI, final artifact,
  signature, checksum, and diff checks pass.

## Residual risk

Only the current dark appearance was visually compared with the reported issue.
The chosen AppKit semantic color adapts in light and accessibility appearances,
but final human visual acceptance still applies.

## Decision

Verified with automated checks, a final release-style build, and real-window
dark-appearance inspection. No release or human approval is recorded.
