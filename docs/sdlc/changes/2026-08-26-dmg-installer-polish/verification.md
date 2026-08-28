# Verification: Polish and harden the Utter DMG installer

## Evidence

The implementation was rebased onto `origin/main` at `7e0689a`. During the
implementation loop, a real Finder inspection caught two defects before PR
preparation: dark artwork made Finder labels hard to read, and hiding the
`.app` extension added FinderInfo that invalidated strict mounted-app signature
verification. Both were corrected before the latest-base verification run.

| Check | Result | Evidence |
|---|---|---|
| `python3 scripts/sdlc.py validate --worktree` | Pass | Verified bundle covers every governed changed path |
| `bash scripts/ci-basic-checks.sh` | Pass | SDLC, 13 harness tests, versioning, plist, localization, identifiers, lexicon, resources, conflicts, credentials, and symlink checks passed |
| `swift test` | Pass | 564 XCTest tests, 8 skipped, 0 failures; 1 Swift Testing test passed |
| Clean pinned tool install | Pass | `pip --require-hashes` installed `dmgbuild 1.6.7`, `ds-store 1.3.3`, and `mac-alias 2.2.3` into a new temporary directory |
| Release-style app and DMG build | Pass | `build-app.sh --version=0.0.0 --sign=-`; the built-in release artifact verifier passed |
| Mounted artifact verification | Pass | DMG checksum valid; strict deep code-signature verification passed; app is arm64; Applications resolves to `/Applications`; background contains two image representations |
| Finder layout metadata | Pass | 680 by 440 window; toolbar, sidebar, status bar, and path bar hidden; 112-point icons at `(174, 250)` and `(506, 250)`; background image enabled |
| Real Finder window | Pass with recapture limitation | The same final installer design was inspected in a real Finder window and showed readable, unclipped labels and a clear drag flow. A latest-base recapture attempt failed because ScreenCaptureKit could not start; final-artifact metadata and image representations were rechecked independently |
| `git diff --check` | Pass | No whitespace errors |

## Acceptance criteria

- Branded, readable, unclipped real Finder installation window — pass, with the
  latest-base screenshot recapture limitation recorded above.
- Finder-independent, hash-pinned packaging — pass in clean temporary install
  and repository checks.
- Strict mounted-app signature and release verifier — pass on the latest-base
  release-style build.
- Generated products excluded from Git — pass in final worktree inspection.

## Residual risk

Independent high-risk review, configured release-identity verification, and any
Developer ID notarization run remain external/human gates. The packaging library
also emits non-fatal macOS 26 `hdiutil` deprecation warnings, and the latest-base
Finder screenshot should be spot-checked by the reviewer because the recapture
tool was unavailable.

## Decision

Ready for human review. No human approval is claimed here; approval remains a PR
review and protected-release decision.
