# Spec: Confucius4-R2T2 MLX speech recognition in Utter

**Status:** approved
**Approved-by:** user (chat: "继续，并批准，并继续。")
**Approved-date:** 2026-09-23
**Upstream:** intent.md

## Context

The selected repository is `mlx-community/Confucius4-R2T2-8bit`, an MLX
conversion of `netease-youdao/Confucius4-R2T2`. Its published `config.json`
declares `Qwen3ASRForConditionalGeneration` and 8-bit affine quantization. It
contains `model.safetensors`, its index, tokenizer files, and an audio
preprocessor configuration. The repository totals about 2.48 GB.

Utter already has one Qwen3-ASR path: `AppSettings.qwenASRModel` selects a
repository ID; `ModelCatalog` downloads and validates it; `VoicePipeline` and
`SpeechEngineProvider` create `QwenNativeASREngine` for that model directory;
the engine calls `Qwen3ASRModel.fromModelDirectory` from the pinned
`mlx-audio-swift` 0.1.3 dependency. Completed audio is converted to 16 kHz
mono PCM and sent through the existing output pipeline. There is no GGUF
runtime. The model card asserts Swift loader compatibility, but this exact
repository and pinned dependency have not been tested together in Utter.

The Qwen3 model list currently only returns the default model. Its active-row
indicator uses `SpeechEngineType.asrModelID`, which is always the default Qwen
ID even when `settings.qwenASRModel` changes. That must be corrected when a
second Qwen-compatible model is offered.

## Design

- Register the exact MLX repository ID in `ModelCatalog.defaultASRModels` and
  show it in the existing Qwen3-ASR model list. Keep one persisted selection,
  `settings.qwenASRModel`, as the source of truth. The Qwen3 list's active row
  reads that setting. No second runtime state or speech-engine enum case is
  needed.
- Require the same complete MLX file set as the existing Qwen3-ASR model,
  including weights, index, config, preprocessor, and tokenizer files. Reuse
  the generation-staged Hub download, cancellation, retry, and deletion path.
  Add an explicit download-size estimate near the repository metadata value.
- Reuse `QwenNativeASREngine` and its path-based reload behavior. First prove
  an actual load and Chinese/English transcription with the pinned Swift
  dependency. If 8-bit loading fails, diagnose that compatibility issue before
  considering a dependency update; do not silently route to another model.
- Keep whole-recording recognition. The R2T2 model is trained for stable-prefix
  streaming, but Utter's current Swift Qwen path calls whole-clip `generate`.
  Check a recording stopped mid-sentence for a trailing `|` or lost final
  words. If it reproduces, add model-specific tail silence to the prepared
  audio and verify recovery; stripping `|` alone is insufficient.
- Localize the model name/hint and make the Qwen3 section text accurately
  describe both selectable MLX models. The model remains an ASR option, never
  an LLM option.

This is an extension of the existing model boundary. Repeated small patches to
callers would duplicate selection state; a replacement of the Qwen engine would
add migration and regression cost without a demonstrated need. A whole-app or
whole-ASR rewrite would require substantially more validation and has no
benefit for this model addition.

## Safety and failure modes

- Audio remains local. Downloaded weights come from the named Hugging Face
  repository through the existing Hub client. No audio is sent to that host.
- A partial or empty weight/config/tokenizer file must remain incomplete.
  A load failure is surfaced as an error, not a ready model or a silent
  substitute. Existing download operations remain serialized by model ID.
- Switching between the two Qwen-compatible models creates the engine from
  the selected path. Deleting the active model unloads it and leaves the
  selection visibly unavailable until another model is chosen or downloaded.
- The NetEase license is not MIT. Its English text requires retaining notices
  and the agreement in copies of the model, and imposes downstream terms.
  Distribution and in-app download presentation require owner/legal review
  before release. Keep a link to the model license and conversion notice in
  the model UI or accompanying documentation; do not bundle weights in the app.

## Test strategy

- Contract tests: model list and persisted selection, active-row selection,
  required-file validation (including missing/zero-byte weights), and
  download-size hint consistency.
- Failure tests: incomplete download, cancellation/retry, failed model load,
  and switch/delete of the active model. Reuse existing download tests where
  their behavior is already covered; add only missing assertions.
- Runtime probe on Apple Silicon: load the downloaded 8-bit model using the
  pinned Swift package, transcribe one Chinese and one English clip, then a
  clip ending mid-sentence. Record exact output, elapsed time, memory use,
  and whether tail padding is needed.
- Run `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`,
  `swift test`, a release-style build, and real-window light/dark checks of
  the model selection/download UI after implementation. Record evidence in
  `verification.md`.

## Rollout and rollback

Do not release until the runtime probe and license review pass. The feature
adds a selectable model and does not change the default. If load or output
quality fails, remove or hide only the new catalog entry and keep existing
models and their stored files untouched. If a release is rolled back, the
prior app continues to use its existing Qwen model; the new cached repository
can be removed through model management or storage cleanup.

## Design approval decisions

- Approve placing Confucius4 beneath the existing Qwen3-ASR engine picker
  rather than adding a separate engine segment.
- Approve whole-recording recognition as the initial scope. Streaming partial
  text is a separate feature with a different runtime contract.
- Release remains gated on successful pinned-runtime inference and model
  license review.
