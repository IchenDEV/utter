# Spec: Use native System Settings form structure

## Context

The rejected pass still owns section surfaces in custom SwiftUI code. It also
keeps a 96-point page header, a 72-point illustration, and 44-point icon choice
tiles. These choices dominate the visual hierarchy and prevent the result from
matching macOS System Settings even when the section title sits outside.

## Layout specification

The fixed settings shell remains unchanged. Settings content uses one native
single-column grid:

- `Form` with `.formStyle(.grouped)` owns content margins and vertical rhythm;
- `Section` owns external headers, semantic group fill, corner shape, and row
  separators;
- standard macOS controls remain at native compact height;
- long editors and data lists may define content height, but do not draw an
  additional section-level rounded rectangle;
- Activity metrics retain their chart/card layout because they present data,
  while their decorative page illustration header is removed.

This replaces the earlier hand-tuned 28/14/8 custom-card grid. The system form
is the geometry source of truth, so new settings do not invent new margins,
corner radii, or section spacing.

## Design

Delete the custom section simulator from settings-page composition. General,
Models, Style, Integrations, and About render their content directly in grouped
forms. Page titles remain discoverable through the selected tab and window;
duplicate promotional headers and illustrations are removed.

Replace the style cards and model engine/family icon strips with segmented
pickers backed by the existing settings bindings and selection callbacks.
Activity keeps its segmented Insights/History control in a compact top strip.

## Safety and failure modes

- Grouped Form can impose different spacing than custom scroll views. The fixed
  window is inspected in both languages and appearances.
- Replacing custom choices must preserve unload/load callbacks for remote and
  local model-family changes.
- Long model and dictionary lists must remain scroll-contained and reachable.

## Test strategy

- Compile and run the full Swift test suite to catch view/type regressions.
- Run repository SDLC, localization, and invariant checks.
- Build the application and inspect all six tabs in the real fixed-size window
  in Chinese and English, in light and dark appearances.

## Rollout and rollback

Merge through normal PR review. Stop if controls clip, a model-selection
callback changes, or grouped sections regress in either appearance. Roll back
by reverting this bundle and its view composition changes; no data migration is
involved.
