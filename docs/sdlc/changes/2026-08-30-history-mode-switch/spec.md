# Spec: Integrate the history mode switch into page controls

## Context

The existing picker is correctly modeled as a native content-view switch, but
its parent-level centered strip creates a visually detached third navigation
layer between the settings tabs and the history content.

## Design

### Layout specification

The fixed settings shell and 28-point history content inset remain unchanged.
The separate centered mode strip is removed.

- Mode control: native segmented picker, small control size, 140-point width.
- Insights header: flexible title/subtitle, then the mode control, then the
  time-range picker, with 12-point spacing.
- History toolbar: flexible search field, record count, then the same mode
  control, retention picker, and clear action, with 10-point spacing.
- No additional background, border, divider, or absolute positioning.

The mode control remains visually stable near the trailing side of both modes'
top control rows while the adjacent contextual controls may differ.

## Behavior

Both placements bind to the single `HistorySection` state owned by
`HistoryStatsView`. Switching modes replaces the content while preserving the
analytics range, search, retention, and history data behavior already owned by
their respective views.

## Safety and failure modes

- English labels can widen the header. The mode control has a fixed compact
  width and the title region remains flexible.
- The History toolbar contains more controls. Its search field uses a bounded
  width so trailing controls remain reachable at 760 points.
- Moving the picker must not create separate selection state in either child.

## Test strategy

- Compile and run the full Swift test suite.
- Run repository SDLC and invariant checks.
- Build the app and inspect Insights and History in Chinese and English, light
  and dark, at the fixed 760 by 680 content size.

## Rollout and rollback

Merge through normal review after real-window approval. Revert this bundle and
restore the parent-level mode strip if either toolbar clips. No persisted data
or setting migration is involved.
