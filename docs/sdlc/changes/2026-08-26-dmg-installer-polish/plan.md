# Plan: Polish and harden the Utter DMG installer

## Work items

- [x] Audit the existing DMG stage and release workflow.
- [x] Render restrained 1x and 2x branded installation backgrounds.
- [x] Add deterministic Finder geometry, icon positions, Applications symlink,
  and volume icon metadata without Finder automation.
- [x] Pin packaging dependencies by version and SHA-256 below the ignored build
  cache.
- [x] Preserve strict mounted-app signature validity and the latest release
  artifact verifier.
- [x] Re-run all repository, unit, release-build, artifact, and real-window
  checks on the latest `origin/main` base.
- [x] Record final evidence and residual risk for review.

## Verification plan

- [x] `python3 scripts/sdlc.py validate --worktree`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`
- [x] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./scripts/build-app.sh --version=0.0.0 --sign=-`
- [x] Inspect the mounted DMG, strict code signature, layout metadata, Retina
  background representations, architecture, symlink, checksum, and real Finder
  window.
- [x] `git diff --check`

## Human gates

An independent reviewer must accept the high-risk packaging/dependency change
and its rollback before merge. The protected release environment separately
owns the configured signing identity, Developer ID/notarization path, and public
release authorization.
