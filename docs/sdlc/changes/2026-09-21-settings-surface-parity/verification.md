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
| [Baseline] User screenshot sampling | Pass | Reference System Settings: content `#FFFFFF` / box `#F7F7F7`; Pre-fix Utter: page `#F6F6F6` / card `#FFFFFF` (roles inverted) |
| [Direct probe] AppKit semantic colors (headless / ambient) | Pass | Light: window `#FFFFFF`, underPage `#F6F6F6`; Dark: window `#1E1E1E`, underPage `#282828` |
| [Real-window capture] Running app in light appearance | Pass | `dist/Utter.app` (dev-signed) Activity tab: page `#FFFFFF`, grouped boxes `#F7F7F7` (matches System Settings content `#FFFFFF` / box `#F7F7F7`) |
| [Real-window capture] Running app in dark appearance | Pass | Same window with dark appearance: page `#252525`, grouped boxes `#303030` (adapts to window compositing / contrast hierarchy) |

The real-window captures were produced by building and launching the app, forcing
light/dark appearance, and caching the live window's `contentView` into a PNG
(`cacheDisplay(in:to:)`). They are not mockups: they are the actual SwiftUI tab
rendering.

### Test revision in `09bb96f0` / `c30047df` and reproducible mutation steps

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

#### Reproducible mutation steps

1. **Mutation 1 (Role inversion)**: In `Sources/UI/SettingsSurface.swift`, swap `pageSemanticColor` and `cardSemanticColor`:
   ```swift
   static var pageSemanticColor: NSColor { .underPageBackgroundColor }
   static var cardSemanticColor: NSColor { .windowBackgroundColor }
   ```
   Command:
   ```bash
   swift test --filter SettingsSurfaceTests
   ```
   Observed result: 4 tests fail across both `.aqua` and `.darkAqua`:
   - `testPageSurfaceRendersAsWindowBackgroundColor`: failed (rendered `#F6F6F6`, expected `#FFFFFF`)
   - `testCardSurfaceRendersAsUnderPageBackgroundColor`: failed (rendered `#FFFFFF`, expected `#F6F6F6`)
   - `testSurfaceSemanticColorRoles`: failed (identity check)
   - `testAppearancesProduceDistinctRenderings`: failed (contrast / distinctness)

2. **Mutation 2 (Arbitrary color corruption)**: In `Sources/UI/SettingsSurface.swift`, alter `cardSemanticColor` to an incorrect color:
   ```swift
   static var cardSemanticColor: NSColor { .systemRed }
   ```
   Command:
   ```bash
   swift test --filter SettingsSurfaceTests
   ```
   Observed result: 2 tests fail:
   - `testCardSurfaceRendersAsUnderPageBackgroundColor`: failed (rendered `#FF3B30`, expected `#F6F6F6`)
   - `testSurfaceSemanticColorRoles`: failed (identity check)

3. **Restore baseline**: Revert `Sources/UI/SettingsSurface.swift` back to production implementation:
   ```swift
   static var pageSemanticColor: NSColor { .windowBackgroundColor }
   static var cardSemanticColor: NSColor { .underPageBackgroundColor }
   ```
   Command:
   ```bash
   swift test --filter SettingsSurfaceTests
   ```
   Observed result: 6 tests pass, 0 failures.

## Acceptance criteria

- Page surfaces use `windowBackgroundColor`; boxes use
  `underPageBackgroundColor` — pass (`SettingsSurfaceTests` render assertions,
  the mutation counterexamples, and the real-window captures).
- Box fill distinct from the page — pass (`testPageAndCardSeparateVisibly`, and
  visible in both captures).
- All check scripts and `swift test` pass — pass.

## Scope of verification and remaining human acceptance items

### Verified evidence (completed)
- **Production seams & test suite**: `SettingsSurface` routes through `pageSemanticColor` / `cardSemanticColor`. `SettingsSurfaceTests` (6 tests) rasterizes views in `NSHostingView` under `.aqua` and `.darkAqua`, passes deterministically, and catches role-swap and color-corruption regressions. Full suite: 639 tests passed, 0 failures.
- **Real-window live captures**: `dist/Utter.app` running window Activity tab captured in standard light (`#FFFFFF` page / `#F7F7F7` cards) and dark (`#252525` page / `#303030` cards), matching the user reference screenshot palette.
- **CI / SDLC gates**: `bash scripts/ci-basic-checks.sh` and `bash scripts/sdlc-checks.sh` pass.

### Remaining unverified scope (reserved for human acceptance / CTO)
- **Remaining tabs and onboarding real-device matrix**: Activity tab is verified with real-window captures. The other 5 settings tabs (General, Models, Permissions, Style, About) and the onboarding window share the identical `SettingsSurface` seams and `SettingsPageLayout`, but visual inspection on physical hardware across standard light, standard dark, and increased contrast remains to be completed by a reviewer with interactive desktop control (scripted tab switching is unavailable in headless CLI as SwiftUI tab bars do not expose `NSButton` subviews).
- **Formal SDLC approvals**: `intent.md`, `spec.md`, and `verification.md` remain in `pending approval` status and must be formally signed off by an authorized human; automated CI passes cannot substitute for human approval.

## Decision

Ready for review. Human approval is recorded separately.
