# Spec: Restore the Dock icon in development app bundles

## Context

The release builder copies `Resources/Info.plist` and compiles/copies the app
icon into `Contents/Resources`. The development builder instead synthesized a
second plist and copied only SwiftPM resource bundles, allowing the two bundle
contracts to drift.

## Design

Copy the canonical repository `Info.plist` into the development bundle. Copy
the existing light, dark, and default `.icns` files to the root Resources
directory before signing. After signing, assert that `CFBundleIconFile` equals
`AppIcon` and that the default root icon is non-empty before any run mode opens
the app.

## Safety and failure modes

- The canonical plist adds the same bundle metadata used in releases; no
  permission or identity value is changed.
- A missing generated icon now fails closed instead of launching an iconless app.
- The pre-generated `.icns` files do not require the slower release asset-catalog
  compilation, keeping the development loop fast.

## Test strategy

Run the original red package-invariant command, `build-and-run.sh --verify`,
code-sign verification, the repository basic checks, and the full Swift tests.
Inspect the packaged plist and root icon directly.

## Rollout and rollback

Use the corrected script for local development builds after review. Revert this
script and bundle if canonical metadata affects development-only startup; the
release pipeline is unchanged.
