# Intent: Integrate the history mode switch into page controls

## Problem

The Insights/History segmented control currently occupies a centered,
full-width strip between the primary settings tabs and the history content. It
looks like a third navigation layer and creates a large empty band that is not
connected to either mode's controls.

## Outcome

The mode switch remains a native segmented control but becomes a compact,
contextual control inside each history mode's top action row.

## Scope

In scope: placement, size, spacing, and shared rendering of the history mode
switch in Insights and History.

Out of scope: primary settings tabs, analytics cards, history data, search and
retention behavior, localization copy, and fixed window geometry.

## Constraints

- Preserve the fixed 760 by 680 settings window and 28-point history inset.
- Keep one selection state shared by both modes.
- Use native compact controls and semantic system styling.
- Preserve history search, retention, analytics range, and data behavior.

## Acceptance criteria

- The switch no longer owns a separate full-width strip or divider.
- It remains visible and keyboard accessible in both modes.
- It aligns to the 28-point content grid and nearby controls without clipping
  in Chinese or English.
- Both modes are inspected in the real fixed-size window in light and dark
  appearances.

## Open questions

None. Human review retains final visual approval.
