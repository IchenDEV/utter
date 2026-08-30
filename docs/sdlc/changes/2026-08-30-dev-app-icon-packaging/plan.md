# Plan: Restore the Dock icon in development app bundles

## Work items

- [x] Reproduce the missing icon metadata and root resource in the built app.
- [x] Compare development and release bundle assembly.
- [x] Reuse canonical metadata and generated icon assets.
- [x] Re-run the exact package invariant and application launch checks.
- [x] Record repository-level validation and residual risk.

## Verification plan

- [x] `bash scripts/build-and-run.sh --verify`
- [x] Packaged plist and root-icon invariant check
- [x] `codesign --verify --deep --strict dist/Utter.app`
- [x] `python3 scripts/sdlc.py validate --worktree`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] `git diff --check`

## Human gates

PR review owns acceptance of the development bundle change. No signing identity,
tag, release, or protected production action is performed by this work.
