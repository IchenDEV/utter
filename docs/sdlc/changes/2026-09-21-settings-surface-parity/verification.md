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
| `swift test` (full suite) | Pass | 639 tests, 10 skipped, 0 failures |
| `swift test --filter SettingsSurfaceTests` | Pass | 6 tests, 0 failures |
| Mutation: swap page/card roles | Fails as required | Both the identity and the light/dark render assertions fail |
| Mutation: recolor card to a wrong color | Fails as required | `testCardSurfaceRendersAsUnderPageBackgroundColor` and the role test fail |
| Screenshot color sampling | Pass | System Settings content `#FFFFFF` / box `#F7F7F7`; Utter page `#F6F6F6` / card `#FFFFFF` |
| Semantic color probe (this machine) | Pass | light: window `#FFFFFF`, underPage `#F6F6F6`; dark: window `#1E1E1E`, underPage `#282828` |
| Real-window rendering, light | Pass | Running `dist/Utter.app` (dev-signed), Settings → Activity: page `#FFFFFF`, grouped boxes `#F7F7F7` |
| Real-window rendering, dark | Pass | Same window with dark appearance: page `#252525`, grouped boxes `#303030` |

The real-window captures were produced by building and launching the app, forcing
light/dark appearance, and caching the live window's `contentView` into a PNG
(`cacheDisplay(in:to:)`). They are not mockups: they are the actual SwiftUI tab
rendering.

### Test revision in `09bb96f0` and the counterexample that drove it

Review found the first revision could not detect a regression: it asserted against
duplicated `NSColor` getters (`pageSRGB` / `cardSRGB`) that were never used by the
render path, so swapping `page` and `card` still passed. The explicit light/dark
case was also ineffective, because a dynamic `NSColor` re-resolves against the
ambient appearance once it leaves `performAsCurrentDrawingAppearance`.

The tests now rasterize the **production** `SettingsSurface.page` / `card` and the
semantic reference `Color(nsColor:)` in an `NSHostingView` with an explicit
`appearance`, so both sides go through the same pipeline and light/dark are
deterministic regardless of the process appearance. (Probed: `ImageRenderer`
ignores `performAsCurrentDrawingAppearance` and always renders ambient; an
`NSHostingView` whose `appearance` is set renders `#FFFFFF` for aqua and
`#1E1E1E` for darkAqua.)

Counterexamples run locally, then reverted:

| Mutation | Result |
|---|---|
| `page` ↔ `card` semantic roles swapped | 4 tests fail, in both light and dark |
| `card` recolored to `systemRed` | 2 tests fail |
| Correct implementation restored | 6 tests pass |

## Acceptance criteria

- Page surfaces use `windowBackgroundColor`; boxes use
  `underPageBackgroundColor` — pass (`SettingsSurfaceTests` render assertions,
  the mutation counterexamples, and the real-window captures).
- Box fill distinct from the page — pass (`testPageAndCardSeparateVisibly`, and
  visible in both captures).
- All check scripts and `swift test` pass — pass.

## Residual risk

- Real-window evidence covers the Activity tab in light and dark. The other five
  tabs and the onboarding window share the same `SettingsSurface` seams and
  `SettingsPageLayout`, but a full per-tab matrix (standard light, standard dark,
  increased contrast) still needs a person with macOS window control, because
  scripted tab switching is not possible here (the SwiftUI tab bar exposes no
  `NSButton` subviews).
- The raw semantic values differ per macOS version; the change tracks the system
  palette by construction rather than pinning values.

## Decision

Ready for review. Human approval is recorded separately.
