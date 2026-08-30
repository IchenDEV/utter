# Plan: Replace the Python SDLC validator with a strict shell gate

**Status:** approved
**Approved-by:** chenli
**Approved-date:** 2026-08-31
**Upstream:** [spec.md](spec.md)

## Work items

- [x] Add `Status`/`Approved-by`/`Approved-date`/`Upstream` headers to templates
- [x] Write `scripts/sdlc-checks.sh`; wire into `scripts/ci-basic-checks.sh` and `.github/workflows/pr.yml`
- [x] Remove `scripts/sdlc.py`, `scripts/sdlc_policy.py`, `scripts/tests/test_sdlc.py`, all `state.json`
- [x] Update AGENTS.md, `docs/sdlc/README.md`, README.md, README_zh.md references

## Verification plan

- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test` (see verification for local environment blocker)

## Human gates

Merge approval — granted by the maintainer's instruction to open and merge the PR.
