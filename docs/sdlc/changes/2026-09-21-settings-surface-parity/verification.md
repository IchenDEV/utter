# Verification: Settings surface parity with System Settings

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `swift build` | Pass | `Build of product 'OpenType' complete!` |
| `swift test` (full suite) | Pass | 637 tests, 10 skipped, 0 failures |
| `swift test --filter SettingsSurfaceTests` | Pass | 4 tests, 0 failures |
| Screenshot color sampling | Pass | System Settings content `#FFFFFF` / box `#F7F7F7`; Utter page `#F6F6F6` / card `#FFFFFF` |
| Semantic color probe (this machine) | Pass | light: window `#FFFFFF`, underPage `#F6F6F6`; dark: window `#1E1E1E`, underPage `#282828` |
| Real-window rendering, light | Pass | Running `dist/Utter.app` (dev-signed), Settings → Activity: page `#FFFFFF`, grouped boxes `#F6F6F6`, light appearance |
| Real-window rendering, dark | Pass | Same window with forced dark appearance: page `#1E1E1E`, grouped boxes `#282828` |

The real-window captures were produced by building and launching the app, setting
`NSApp.appearance` to light/dark, and caching the live window's `contentView`
into a PNG (`cacheDisplay(in:to:)`). They are not mockups: they are the actual
SwiftUI tab rendering.

### Previous CI failure and its fix

The earlier head `4bc77ca` failed `Contract & Tests` /
`SettingsSurfaceTests.testCardSurfaceRendersUnderPageBackgroundColor`, where all
three RGB assertions returned `0.6548` against an expected `0.5882`. The test was
rendering the dynamic `NSColor.underPageBackgroundColor` through `ImageRenderer`
and comparing pixels against the process-ambient color. A headless runner
resolves that semantic color through a different color pipeline than a user
session, so the rendered pixel `#F8F8F8` did not match the ambient `#F6F6F6`.

The test now resolves both sides through the sRGB color space
(`SettingsSurface.pageSRGB` / `cardSRGB` against `NSColor.windowBackgroundColor` /
`.underPageBackgroundColor`) and additionally checks that the two surfaces are
distinct and that each resolves inside explicit `.aqua` / `.darkAqua`
appearances. This is deterministic on a runner and on a user session.

## Acceptance criteria

- Page surfaces use `windowBackgroundColor`; boxes use
  `underPageBackgroundColor` — pass (`SettingsSurfaceTests` component
  assertions, plus the real-window captures above).
- Box fill distinct from the page — pass
  (`testSurfacesUseDifferentSemanticColors`, and visible in both captures).
- All check scripts and `swift test` pass — pass.

## Residual risk

- Real-window evidence covers the Activity tab in light and dark (the tab where
  the page/box contrast is most visible). The General, Models, Style,
  Integrations, and About tabs and the onboarding window share the same
  `SettingsSurface` seams and `SettingsPageLayout`, but were not each captured;
  scripted tab switching did not work in this environment (the SwiftUI tab bar
  exposes no `NSButton` subviews).
- The raw semantic values differ per macOS version; the change tracks the system
  palette by construction rather than pinning values.

## Decision

Ready for review. Human approval is recorded separately.
