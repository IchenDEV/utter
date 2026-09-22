# Spec: Settings surface parity with System Settings

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `intent.md`

## Context

`SettingsView` and `settingsPageSurface()` painted
`Color(nsColor: .underPageBackgroundColor)` from the approved 2026-08-31
`settings-semantic-background` change. Grouped cards and boxes painted
`Color(nsColor: .controlBackgroundColor)`. On macOS 26/27 those resolve to:

| Semantic color | Light | Dark |
|---|---|---|
| `windowBackgroundColor` | `#FFFFFF` | `#1E1E1E` |
| `underPageBackgroundColor` | `#F6F6F6` | `#282828` |
| `controlBackgroundColor` | `#FFFFFF` | `#1E1E1E` |

System Settings samples (light, from the user's screenshot): content `#FFFFFF`,
box `#F7F7F7`. So the correct mapping is page = `windowBackgroundColor`, box =
`underPageBackgroundColor`.

## Design

Add `SettingsSurface` (a small enum namespace) with three seams:
`page` (`windowBackgroundColor`), `card` (`underPageBackgroundColor`), and
`cardStroke` (`separatorColor`). Replace the ad-hoc colors:

- `SettingsView` root and `settingsPageSurface()` use `SettingsSurface.page`.
- `SettingsCardBackground` uses `SettingsSurface.card` / `cardStroke`.
- `HistoryInsightsOverview.cardBackground` uses the same.
- The grouped boxes in `OnboardingView` and `PermissionsView` use
  `SettingsSurface.card` / `cardStroke` instead of `controlBackgroundColor`.

Editing surfaces (`DictionaryStyleView`) keep `textBackgroundColor`, so text
fields stay white.

## Safety and failure modes

Visual-only change. No behavior, data, privacy, or permission impact. Fixed
colors are avoided, so contrast in increased-contrast and dark appearances comes
from AppKit. Risk is limited to contrast regressions, which the distinctness test
and review of light/dark appearances cover.

## Test strategy

`SettingsSurfaceTests` rasterizes the production `SettingsSurface.page` / `card`
and the semantic reference `Color(nsColor:)` in an `NSHostingView` with an explicit
`NSAppearance` (`.aqua` / `.darkAqua`), ensuring both sides share the exact same
rendering pipeline and that dynamic colors resolve deterministically regardless of
ambient process appearance (addressing `ImageRenderer`'s limitation of ignoring
`performAsCurrentDrawingAppearance`). It asserts pixel equality in sRGB (within
color-management tolerance) plus a page/card distinctness assertion so boxes stay
visible. Full `swift test`, and the two check scripts.

## Rollout and rollback

Ships with the next Utter release. Rollback is reverting the commit; the change
touches only color seams.
