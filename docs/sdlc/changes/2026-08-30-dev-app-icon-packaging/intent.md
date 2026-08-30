# Intent: Restore the Dock icon in development app bundles

## Problem

`scripts/build-and-run.sh` writes a reduced `Info.plist` without app-icon keys
and leaves `AppIcon.icns` nested inside a SwiftPM resource bundle. When the app
uses its default system icon preference, AppKit clears the runtime override and
Dock has no bundle icon to display.

## Outcome

Development app bundles use the canonical metadata and expose the pre-generated
icon files at the bundle root expected by Dock and LaunchServices.

## Scope

In scope: development app assembly and deterministic icon checks. Out of scope:
icon artwork, release packaging, signing identities, and runtime icon settings.

## Constraints

- Preserve the current fast SwiftPM development build.
- Do not weaken or bypass existing code signing.
- Reuse canonical metadata and generated icon assets instead of duplicating them.

## Acceptance criteria

- The development plist declares `CFBundleIconFile=AppIcon`.
- `Contents/Resources/AppIcon.icns` exists and is non-empty.
- Missing icon metadata or the root icon makes packaging fail.
- The signed development app still launches successfully.

## Open questions

None. The release builder already establishes the expected bundle contract.
