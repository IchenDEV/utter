# Intent: Polish and harden the Utter DMG installer

## Problem

The release DMG currently contains only `Utter.app` and an Applications
symlink. Finder chooses the window size, icon placement, and background, so the
installation flow looks unfinished and can vary with the packager's Finder
state. The existing path also has no Retina-aware installation artwork or
deterministic layout metadata.

## Outcome

Opening a release DMG shows a compact Utter-branded Finder window with the app
and Applications folder aligned around a clear drag arrow. Labels remain
readable in the user's current macOS appearance, and the same result is produced
locally and in release CI without scripting Finder.

## Scope

In scope: DMG background rendering, Finder window metadata, icon positions,
volume presentation, deterministic packaging dependencies, and the existing
`build-app.sh` DMG stage.

Out of scope: app runtime UI, application behavior, entitlements, signing
identity selection, notarization policy, release credentials, or installing the
app during validation.

## Constraints

- Preserve the current Swift Package and release-signing flow.
- Keep generated PNG/TIFF files, downloaded Python packages, `.app`, `.dmg`, and
  screenshots out of Git.
- Use only macOS-compatible tooling available to local builders and GitHub macOS
  runners; fail rather than silently ship an unstyled or unverifiable image.
- Treat local ad-hoc signing as packaging evidence, not public distribution
  evidence.

## Acceptance criteria

- The real Finder window opens at 680 by 440 points with Utter and Applications
  icons at the intended positions, a readable light background, and no clipped
  installation copy.
- The background contains 1x and 2x representations and the DMG has a custom
  volume icon.
- Packaging writes Finder layout metadata without launching or controlling
  Finder.
- Packaging dependencies are version- and SHA-256-pinned and cached only below
  `.build`.
- `verify-release-artifact.sh` and strict mounted-app code-signature validation
  accept the locally generated artifact.

## Open questions

None. Human review still decides whether the new packaging dependency and
visual treatment are accepted for release.
