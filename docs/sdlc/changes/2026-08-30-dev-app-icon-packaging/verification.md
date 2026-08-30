# Verification: Restore the Dock icon in development app bundles

## Evidence

- The pre-fix package invariant failed deterministically: the development plist
  had no `CFBundleIconFile` and `Contents/Resources/AppIcon.icns` was absent.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash
  scripts/build-and-run.sh --verify` built, signed, launched, and detected the
  corrected development app.
- The same package invariant now reports `CFBundleIconFile=AppIcon`, finds the
  non-empty root icon, and returns PASS.
- `codesign --verify --deep --strict --verbose=2 dist/Utter.app` passed. The
  packaged and source `AppIcon.icns` files share SHA-256
  `ecb90dc46a59f11944074e8b6bd22dd52a261bf8f0264e4c6bd00876b6b6a70f`.
- The packaged `.icns` was rendered to PNG and visually inspected as the
  intended Utter microphone icon.
- `bash scripts/ci-basic-checks.sh` passed all SDLC, localization, identifier,
  resource, conflict, secret-file, symlink, and deterministic lexicon checks.
- `swift test` passed 565 XCTest tests with 8 intentional skips and no failures;
  the Swift Testing model-upgrade policy test also passed.
- `bash -n scripts/build-and-run.sh`, `python3 scripts/sdlc.py validate
  --worktree`, and `git diff --check` passed.

## Acceptance criteria

- Canonical icon metadata — pass.
- Root Dock icon resource — pass and byte-identical to the source asset.
- Fail-closed packaging invariant — pass; every development run mode checks the
  plist value and root icon before launching.
- Signed app launch — pass.

## Residual risk

The fast development builder copies pre-generated `.icns` files rather than
compiling the release `Assets.car`. The default Dock/LaunchServices icon is now
restored, while the existing runtime PNG path continues to handle explicit
light and dark icon preferences. The release pipeline is unchanged.

## Decision

Verified and ready for PR review. No signing identity, release tag, or production
authorization was changed.
