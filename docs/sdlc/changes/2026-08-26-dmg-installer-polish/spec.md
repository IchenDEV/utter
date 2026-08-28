# Spec: Polish and harden the Utter DMG installer

## Context

`scripts/build-app.sh` already builds with Xcode, assembles `Utter.app`, compiles
appearance-aware app icons, signs the bundle, and verifies release artifacts.
Its previous DMG stage copied the app and Applications symlink into a staging
folder and asked `hdiutil` to compress that folder. It did not create a Finder
layout or installation background.

Finder automation can create `.DS_Store`, but it depends on interactive Finder
state and can be blocked by unrelated Finder dialogs. The packaging path must be
deterministic in both a developer session and GitHub Actions.

## Design

`generate-dmg-background.swift` renders a 680 by 440 AppKit bitmap at 1x and 2x.
The light neutral surface, subtle Utter color accents, centered installation
instruction, and arrow are positioned around the Finder icons rather than
duplicating them in the artwork.

`dmg-settings.py` owns the window rectangle, icon size, icon locations, HFS+
filesystem, UDZO compression, Applications symlink, and volume icon. The build
script installs `dmgbuild`, `ds-store`, and `mac-alias` into
`.build/xcode/dmg-tools` from `dmg-requirements.txt`. Every wheel is pinned by
version and SHA-256, and a versioned stamp avoids repeated installation.

The existing release verifier remains the final build step. No packaging code
changes signing identity selection, entitlements, notarization, or publication.

## Safety and failure modes

- A missing Python 3.10+ runtime, unavailable package index, hash mismatch, or
  import failure stops the build; it does not fall back to an unstyled DMG.
- Downloaded code is isolated under ignored `.build` paths and never shipped in
  `Utter.app`.
- Finder extension-hiding metadata is not written to `Utter.app`, because that
  extended attribute makes strict code-signature verification fail.
- A corrupt tool cache fails during module import or DMG creation. Removing the
  ignored cache allows a clean hash-verified reinstall.
- The packaging library currently emits macOS 26 deprecation warnings for its
  internal `hdiutil` calls; artifact verification remains the acceptance gate.

## Test strategy

- Validate shell syntax, Python syntax, Swift background rendering, repository
  policy, and the complete Swift test suite.
- Build a release-style ad-hoc app and DMG on the latest `main` base.
- Verify the DMG checksum, Applications symlink, mounted app signature, arm64
  executable, 1x/2x TIFF representations, and exact `.DS_Store` geometry.
- Open the final image through Finder and inspect the actual title bar, artwork,
  icon labels, spacing, arrow, and lower-edge clipping without installing or
  launching the app.

## Rollout and rollback

Merge through the normal PR and release review path. The next release workflow
build exercises the same DMG stage with its configured signing identity and
artifact verifier. Stop if clean-runner dependency installation or mounted-DMG
verification fails. Roll back by reverting this change, which restores the
previous plain `hdiutil -srcfolder` image without changing app binaries or user
data.
