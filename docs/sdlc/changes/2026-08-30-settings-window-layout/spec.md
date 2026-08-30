# Spec: Stabilize the settings window and shared layout

## Context

`AppDelegate.openSettings()` creates a resizable AppKit window while
`SettingsView` only defines minimum dimensions. Custom scroll content and
grouped `Form` tabs currently inherit different outer content margins, while
the native grouped form settles on a predictable reading width at the compact
window size. Decorative page illustrations add a second visual hierarchy that
does not belong in the final native-form direction.

## Design

The settings shell has one geometry contract: a 760 by 680 content area, no
`.resizable` style mask, and equal minimum and maximum content sizes. The root
SwiftUI view uses the same exact frame so restored AppKit window state cannot
produce a second layout width.

Native settings tabs use grouped `Form` and `Section` geometry as their source
of truth. Activity data cards and history record cards keep a shared 28-point
content inset. Decorative page headers and illustrations are removed rather
than replaced with another custom icon treatment.

## Safety and failure modes

- Fixed sizing can expose clipping that resizing previously hid. The retained
  scroll views and form scrolling contain long content; every tab is inspected
  at the fixed size in both supported UI languages.
- Removing the resize style must not remove close or minimize behavior. Those
  style masks remain present.
- Semantic colors and native controls keep the interface compatible with dark
  mode and accessibility contrast.

## Test strategy

- Unit coverage asserts the exact content dimensions and absence of the
  `.resizable` style mask.
- Repository policy, localization, compilation, and the full Swift test suite
  exercise the implementation.
- A real built app verifies the fixed window geometry, disabled resize/zoom
  affordance, all six tabs, Chinese/English copy, and light/dark rendering.

## Rollout and rollback

Merge through normal PR review. Stop if any tab clips at 760 by 680 or if the
window can still be resized after relaunch/restored state. Roll back by reverting
this bundle and its UI changes; no user data or setting persistence changes.
