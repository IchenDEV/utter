# Intent: Settings surface parity with System Settings

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** —

## Problem

The user reports that the app's gray background "does not look like the system's
mainstream palette" and asks for the colors used by System Settings.

Measured from the attached screenshots (sampled with an sRGB reader):

- System Settings (light): content pane `#FFFFFF`, grouped boxes `#F7F7F7`.
- Utter (light): page `#F6F6F6`, cards `#FFFFFF`.

Utter uses the two semantic grays the other way round: the page is gray and the
boxes are white, while System Settings is a white pane with slightly offset
boxes. On this machine `windowBackgroundColor` is `#FFFFFF` light / `#1E1E1E`
dark and `underPageBackgroundColor` is `#F6F6F6` light / `#282828` dark, so the
current page choice (`underPageBackgroundColor`) is exactly the off-system gray.

## Outcome

Every settings and onboarding surface uses the system semantic palette in the
same roles as System Settings: page/window background from
`windowBackgroundColor`, grouped boxes from `underPageBackgroundColor`. Light,
dark, and increased-contrast appearances adapt without fixed colors.

## Scope

Affected: settings shell and page surfaces, grouped cards/boxes in history
insights, model management, permissions, style, integrations, about, and the
onboarding permission list.

Non-goals: layout, spacing, typography, the recording overlay colors, the
waveform, or the app icon. No appearance override or custom material layer.

## Constraints

- AppKit semantic colors only; no fixed RGB values.
- Follow light and dark appearances automatically.
- List/editor surfaces that use `textBackgroundColor` keep a white editing
  surface.
- One central seam for the two surfaces so future changes stay consistent.

## Acceptance criteria

- Page/window surfaces render `windowBackgroundColor`; grouped boxes render
  `underPageBackgroundColor`, in both appearances.
- The box fill is visibly distinct from the page so the grouping still reads.
- Rendered swatches match the semantic colors within color-management tolerance
  (`SettingsSurfaceTests`).
- `swift test`, `scripts/ci-basic-checks.sh`, and `scripts/sdlc-checks.sh` pass.

## Open questions

None.
