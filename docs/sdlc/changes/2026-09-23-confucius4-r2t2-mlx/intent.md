# Intent: Confucius4-R2T2 MLX speech recognition in Utter

**Status:** approved
**Approved-by:** user (chat: "ok，批准")
**Approved-date:** 2026-09-23
**Upstream:** —

## Problem

Utter cannot select or run the user-requested Confucius4-R2T2 speech-recognition
model. The original linked repository contains GGUF weights, whereas Utter's
existing local Qwen3-ASR engine loads MLX weights.

## Outcome

A user can select Confucius4-R2T2 as a local speech engine, download
`mlx-community/Confucius4-R2T2-8bit` from within Utter, and transcribe a
completed recording without sending audio to a remote service.

## Scope

Affected: local ASR model catalog and download management, speech-engine
selection, model status, and localized UI text. Reuse the existing Qwen3-ASR
MLX runtime if a real load and transcription test confirms compatibility.

The initial outcome covers completed recordings. Live partial transcripts are
outside this change unless the design review identifies a supported runtime
and the user explicitly expands the scope.

## Constraints

- Use the MLX conversion of the same upstream
  `netease-youdao/Confucius4-R2T2` model, not the GGUF files.
- Keep recognition on device and preserve the current recording, cancellation,
  model-switching, and model-deletion behavior.
- Confirm compatibility with Utter's pinned `mlx-audio-swift` version 0.1.3
  through actual inference; the model card's compatibility claim alone is not
  sufficient.
- The repository applies the NetEase Model Use License Agreement. Review
  distribution and attribution requirements before shipping binaries or
  enabling automated downloads in a release.

## Acceptance criteria

- The speech-engine picker identifies Confucius4-R2T2 as a local ASR option,
  with English and Chinese UI text.
- Download, completion checks, cancellation, retry, and deletion work for the
  MLX repository; missing or empty required files cannot appear ready.
- Selecting the model and ending a recording produces text through Utter's
  existing output pipeline, entirely on device.
- Switching away from this model leaves existing speech engines functional.
- A short Chinese clip, an English clip, and a clip ending mid-sentence are
  checked against the actual runtime; the latter must retain the final words.
- Contract and failure-path tests cover model readiness and runtime errors;
  repository checks, unit tests, and a release-style app build pass.

## Open questions

- Does the pinned Swift runtime decode this specific 8-bit conversion correctly,
  including the model's stable-prefix end marker and final words?
- Does the model license permit the intended in-app distribution and download
  flow, and what attribution is required?
