# Plan: Integrate the history mode switch into page controls

## Work items

- [x] Record the awkward third-layer navigation problem and layout target.
- [x] Extract one compact shared history mode picker.
- [x] Place it in the Insights header and History toolbar.
- [x] Verify both modes across languages and appearances in the real window.
- [x] Record automated and visual evidence.

## Verification plan

- [x] `python3 scripts/sdlc.py validate --worktree`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] `bash scripts/build-and-run.sh --verify`
- [x] Real-window Chinese/English light/dark inspection of both modes
- [x] `git diff --check`

## Human gates

The requested redesign is the product direction. A reviewer must still approve
the real-window result before merge; this implementation records no human
approval.
