# Plan: Stabilize the settings window and shared layout

## Work items

- [x] Record the fixed shell and shared inner-grid constraints.
- [x] Make the AppKit and SwiftUI settings surfaces use one exact content size.
- [x] Align native grouped forms and Activity data content to their shared grid.
- [x] Remove decorative page-header illustrations from the final settings UI.
- [x] Add focused fixed-window regression coverage.
- [x] Inspect every tab in the real fixed-size window in both languages and
  appearances.
- [x] Record current verification evidence and residual risk.

## Verification plan

- [x] `python3 scripts/sdlc.py validate --worktree`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] `bash scripts/build-and-run.sh --verify`
- [x] Real-window Chinese/English and light/dark inspection of all six tabs
- [x] `git diff --check`

## Human gates

The requested fixed-window behavior is the product direction. A reviewer must
still approve the visual result and the intentional macOS window-management
exception before merge; no approval is recorded by this implementation.
