# Intent: Match the macOS settings background hierarchy

## Problem

The settings shell forces `windowBackgroundColor` behind every tab. In dark
appearance that semantic color is substantially darker than the page surface
used by macOS Settings, so Utter reads as a near-black canvas beside the system
window.

## Outcome

The settings window uses the macOS semantic under-page background while keeping
the existing grouped sections, cards, controls, spacing, and fixed window size.

## Scope

Only the shared settings shell and page surface colors change. Tab content,
layout, behavior, model selection, other windows, and overlays are out of scope.

## Constraints

- Use an AppKit semantic color rather than a fixed RGB value.
- Keep the existing section/card contrast and all six tab layouts unchanged.
- Do not add appearance preferences or a custom visual-effect layer.

## Acceptance criteria

- The shared settings shell and page surfaces use `underPageBackgroundColor`.
- The real dark-appearance settings window has the lighter system-like page
  hierarchy without clipping or reducing text/control contrast.
- Existing automated tests and the release-style build continue to pass.

## Open questions

Final visual acceptance remains a maintainer decision.
