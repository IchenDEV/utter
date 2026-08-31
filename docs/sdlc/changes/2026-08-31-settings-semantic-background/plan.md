# Plan: Match the macOS settings background hierarchy

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [spec.md](spec.md)

## Work items

- [x] Identify the shared forced background used by every settings tab.
- [x] Replace it with the macOS semantic under-page background.
- [x] Inspect Activity and the ANE model pane in the real dark window.
- [x] Record current evidence and residual risk.

## Verification plan

- [x] Real-window dark-appearance inspection
- [x] `swift test`
- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] Final `bash scripts/build-app.sh`
- [x] `git diff --check`

## Human gates

The user reported the mismatch and requested the system-like background. Final
visual acceptance and any release remain separate maintainer decisions.
