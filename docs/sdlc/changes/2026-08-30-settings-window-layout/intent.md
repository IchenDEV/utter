# Intent: Stabilize the settings window and shared layout

## Problem

The settings window can be resized even though its dense tabbed forms were
designed around one working size. At wider and restored sizes, grouped forms and
custom scroll content no longer share predictable horizontal edges. The first
pass also used decorative page illustrations that were later removed in favor
of native grouped forms.

## Outcome

The Utter settings window always opens at one predictable size and cannot be
resized. Native settings pages use grouped form geometry, while Activity keeps a
shared 28-point content inset for its data presentation.

## Scope

In scope: settings-window size and style, shared settings-page spacing, grouped
form content margins, removal of decorative page illustrations, and focused
regression coverage.

Out of scope: individual setting behavior, tab order, copy, app icon/menu-bar
icon choices, onboarding, the recording overlay, packaging, and release policy.

## Constraints

- Preserve the existing six tabs and lock the window to the prior 760-point
  minimum width and 680-point default height.
- Use semantic system colors and native controls that remain legible in light,
  dark, and increased-contrast appearances.
- Keep existing raster resources available so this UI-only change does not
  broaden into package-resource cleanup.
- Treat the fixed size as an explicit product exception for this single-purpose
  settings utility, not a new rule for other app windows.

## Acceptance criteria

- The settings content area is exactly 760 by 680 points and the window style
  does not permit resizing.
- Settings pages use native grouped-form margins, while Activity data cards and
  history records share a 28-point horizontal content edge.
- No settings page loads or presents a decorative page-header illustration.
- The real settings window is inspected in Chinese and English, in both light
  and dark appearance, with all tabs free of clipping or alignment regressions.

## Open questions

None. Human review still owns final visual acceptance.
