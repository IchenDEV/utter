# Plan: Use native System Settings form structure

## Work items

- [x] Record the rejected custom-card result and native Form target.
- [x] Remove decorative page headers from settings pages and Activity.
- [x] Convert Models, Style, and About to native grouped forms.
- [x] Replace large style, speech-engine, and family tiles with compact native controls.
- [x] Run automated checks and Chinese/English light/dark real-window verification.
- [x] Record current verification evidence and residual risk.

## Verification plan

- [x] `python3 scripts/sdlc.py validate --worktree`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] `bash scripts/build-and-run.sh --verify`
- [x] Real-window Chinese/English light/dark inspection of all six tabs
- [x] `git diff --check`

## Human gates

The requested System Settings fidelity is the product direction. A reviewer
must still approve the real-window result before merge; this implementation does
not record human approval.
