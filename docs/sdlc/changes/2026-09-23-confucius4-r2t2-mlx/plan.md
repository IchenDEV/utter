# Plan: Confucius4-R2T2 MLX speech recognition in Utter

**Status:** approved
**Approved-by:** user (chat: "批准")
**Approved-date:** 2026-09-23
**Upstream:** spec.md

## Work items

- [x] Check the pinned `mlx-audio-swift` loader against the actual 8-bit
  checkpoint in an isolated local probe using existing Chinese and English
  samples. Record load result, output, time, memory, and any `|` suffix. If
  loading fails because the pinned dependency lacks a required feature, stop
  for a design amendment before changing dependencies.
- [x] Add focused contract tests first for the Qwen-compatible model list,
  selected-model identity, required MLX files, and size/hint consistency.
  Reuse the existing Qwen integration test seam for the runtime probe.
- [x] Add `mlx-community/Confucius4-R2T2-8bit` to the ASR catalog and Qwen3
  model list, with a matching required-file contract and repository-size
  estimate. Keep the existing model selection and download transaction path.
- [x] Make the Qwen3 model list's active row follow `settings.qwenASRModel`.
  Add the English and Chinese model hint and update the section description
  so it covers both Qwen-compatible MLX checkpoints.
- [x] Run a mid-sentence stop sample. If final words are lost, add the
  smallest model-specific silence-padding change and a regression test that
  distinguishes recovered text from merely removing `|`.
- [x] Review the exact NetEase license and conversion notices for the in-app
  download flow. Provide the required model-license link and retain notices;
  record the release owner's license decision before any distribution.
- [x] Verify the parallel HTTP application catalog download publishes the full
  Confucius repository, then deletes it through the same catalog path.
- [x] Remove any temporary probe code and keep only a single active Qwen
  runtime path. Review the final diff for stale selection assumptions and
  changes outside this model's boundary.

## Verification plan

- [x] Focused catalog, settings, model-readiness, and failure-path tests.
- [x] Actual 8-bit model inference on Chinese, English, and abruptly ended
  clips; capture output and resource measurements.
- [ ] Cancel/retry and active-model delete/switch checks through the existing
  model-management path.
- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] `bash scripts/build-app.sh --app-only` (release-style Metal packaging).
- [x] Real-window model-selection and download UI review in light and dark
  appearances, including the active-row state after switching models.
- [x] Record results, skipped checks, and residual risk in `verification.md`.

## Human gates

- This plan needs explicit approval before implementation begins, per
  `docs/sdlc/README.md`.
- A failed compatibility probe that requires a dependency or architecture
  change returns to design approval.
- Verification and license/distribution decisions need owner review before
  PR merge or release. No model weights are bundled in the app artifact.
