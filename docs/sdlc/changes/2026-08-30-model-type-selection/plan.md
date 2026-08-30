# Plan: Make custom models an explicit recommended-first type

## Work items

- [x] Record the incorrect custom-type ownership and explicit ordering target.
- [x] Add a red-capable focused test for type order and recommendation state.
- [x] Introduce the explicit Custom formatting type and conditional content.
- [x] Put recommended Qwen first in the speech selector.
- [x] Verify selection callbacks and active custom-model synchronization.
- [x] Run automated and real-window verification.
- [x] Record evidence and residual risk.

## Verification plan

- [x] Focused model-type regression tests
- [x] `python3 scripts/sdlc.py validate --worktree`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] `bash scripts/build-and-run.sh --verify`
- [x] Real-window Chinese/English light/dark inspection
- [x] `git diff --check`

## Human gates

The requested interaction and recommendation order are the product direction.
Because the repository classifies `AppSettings.swift` as a high-risk control
surface, an independent verifier must review the diff and rerun the risk-critical
checks before merge. PR approval and any protected production action remain
human gates; this implementation records no approval.
