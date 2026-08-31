# Spec: Match the macOS settings background hierarchy

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [intent.md](intent.md)

## Context

`SettingsView` and `settingsPageSurface()` both paint
`NSColor.windowBackgroundColor`. The duplicated opaque paint makes the whole
settings window use the dark-window base color even where macOS settings pages
normally use the lighter semantic under-page surface.

## Design

Replace those two shared paints with `NSColor.underPageBackgroundColor`. This is
the smallest change that keeps AppKit responsible for light/dark adaptation and
changes every settings tab consistently. Existing grouped forms and custom
cards continue to own their own semantic control backgrounds.

## Safety and failure modes

The color remains system-provided and appearance-aware. The main risk is reduced
contrast between page and grouped sections, so the actual dark window is
inspected on the affected model page and the card-heavy Activity page.

## Test strategy

Inspect the real built settings window in dark appearance, including Activity
and the ANE model pane, then run repository checks, the full Swift suite, and a
release-style artifact build. No unit test is added for a two-line semantic
color choice because it would only duplicate the implementation.

## Rollout and rollback

Ship through normal review. Roll back the two semantic-color substitutions if
the accepted system appearance or contrast is worse; no user data is affected.
