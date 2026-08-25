# Plan: Adopt an artifact-driven, fail-closed SDLC

## Work items

- [x] Research the first-party AI-native SDLC guidance and separate source facts
  from project-specific decisions.
- [x] Audit current repository artifacts, CI, releases, and live GitHub controls.
- [x] Define risk lanes, lifecycle artifacts, definitions of ready/done, human
  gates, and incident feedback.
- [x] Implement and unit-test deterministic artifact validation.
- [x] Add intent/incident intake and PR evidence templates.
- [x] Add Swift tests and a stable aggregate PR gate.
- [x] Make releases fail closed on ancestry, configured signing identity,
  artifact verification, approval, and checksums while keeping the existing
  self-signed path and requiring notarization for Developer ID.
- [x] Update agent context and contributor-facing entry points.
- [x] Run all applicable local checks and record exact evidence.

## Verification plan

- [x] `python3 scripts/tests/test_sdlc.py`
- [x] `python3 scripts/sdlc.py validate --worktree`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] `bash -n` on changed shell scripts
- [x] parse changed YAML files
- [x] `./scripts/build-app.sh --app-only --sign=-`
- [x] run the release verifier on the local app without claiming Developer ID or
  notarization success
- [x] exercise the current GitHub self-signed release artifact against the
  non-notarized verification branch
- [x] `git diff --check`

## Human gates

The maintainer accepts the intent/design through review of this change. A GitHub
administrator must separately activate the `main` ruleset. A credential holder
must configure and approve the `production` environment and Apple secrets. No
agent may mark those external gates complete from repository evidence alone.
