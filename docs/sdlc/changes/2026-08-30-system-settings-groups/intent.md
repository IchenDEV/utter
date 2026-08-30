# Intent: Use native System Settings form structure

## Problem

The first flattening pass still simulates System Settings with custom white
cards, thin outlines, large icon tiles, and a promotional page header. In the
real fixed-size window it remains visually much farther from macOS System
Settings than the native grouped forms already used by General and Integrations.

## Outcome

Settings pages use actual grouped `Form` and `Section` containers so macOS owns
their fill, corner shape, row height, separators, and header placement. The
decorative page illustration and oversized custom selection tiles are removed.

## Scope

In scope: the settings-page shell and section composition in General, Style and
Rules, Models, Integrations, and About; the Activity-page decorative header;
and oversized custom choices for style, speech engine, and model family.

Out of scope: setting behavior, copy, tab navigation, fixed window geometry,
history metric cards and charts, data persistence, and release policy.

## Constraints

- Preserve the existing fixed 760 by 680 settings window.
- Use semantic system colors and native controls in light, dark, and
  increased-contrast appearances.
- Preserve all setting actions, model load/unload callbacks, and state bindings.
- Do not force history charts and metric cards into a settings form.

## Acceptance criteria

- General, Models, Style, Integrations, and About use native grouped `Form` and
  `Section` surfaces rather than custom card simulations.
- Settings pages do not show the decorative 96-point page header, illustration,
  or accessory badge.
- Speech-engine, language-style, and model-family choices use compact native
  controls instead of large icon tiles.
- The real fixed-size settings window is inspected in Chinese and English, in
  light and dark appearances, without clipping or hierarchy regressions.

## Open questions

None. Human review retains final visual approval.
