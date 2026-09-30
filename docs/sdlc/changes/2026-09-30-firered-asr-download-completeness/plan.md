# Plan: Fix FireRedASR2 (小红书) model download completeness

**Status:** approved
**Approved-by:** chenli (explicit approval in this chat)
**Approved-date:** 2026-09-30
**Upstream:** docs/sdlc/changes/2026-09-30-firered-asr-download-completeness/spec.md
**Risk:** medium — model/runtime behavior

## Work items

- [x] Correct the `mlx-community/FireRedASR2-AED-mlx` case in
  `Sources/Config/ModelCatalogASRFiles.swift` to
  `["config.json", "cmvn.json", "dict.txt", "model.safetensors"]`.
- [x] Add a regression test in `Tests/OpenTypeTests/ConfigurationTests.swift`
  that pins the exact required list and exercises
  `asrRepoContainsRequiredFiles` with and without the weight file.
- [x] Record commands, results, and residual risk in `verification.md`.

## Verification plan

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] Targeted regression test fails on the pre-fix list and passes after.

## Human gates

- Intent and design approval: granted in this chat (2026-09-30).
- PR approval: required before merge.
