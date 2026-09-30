# Intent: Fix FireRedASR2 (小红书) model download completeness

**Status:** approved
**Approved-by:** chenli (explicit approval in this chat)
**Approved-date:** 2026-09-30
**Upstream:** —
**Risk:** medium — model/runtime behavior

## Problem

The `mlx-community/FireRedASR2-AED-mlx` local ASR model (小红书 FireRedASR2)
downloads, but after a successful transfer Utter always reports the model as
incomplete (`model.asr_incomplete`, "模型只下载了一部分。点击继续下载即可接着完成").
The user therefore cannot download a complete model, and the model can never be
selected as ready.

The download itself completes. The published repository is validated by
`ModelCatalog.asrRepoContainsRequiredFiles`, which checks the list returned by
`ModelCatalog.asrRequiredFiles(for:)`. For this model the list is
`["config.json", "tokenizer.json"]`. The upstream repository does not contain
`tokenizer.json`, so the completeness check can never pass.

## Outcome

After a successful `snapshot` download of `mlx-community/FireRedASR2-AED-mlx`,
Utter verifies the model against the files that actually exist in the upstream
repository and that the Swift runtime requires, marks it `.downloaded`, and the
model becomes usable.

## Scope

- Affected: the `FireRedASR2-AED` entry of `ModelCatalog.asrRequiredFiles`, used
  by download status, retry/recovery, and `MLXSTTEngine` readiness.
- Non-goal: changing the upstream repository, the download transport, the
  FireRed engine, or the other ASR models' required-file lists.

## Constraints

- The required-file list must contain only files present in the upstream
  repository and required to load the model with the pinned
  `mlx-audio-swift` 0.1.3 `FireRedASR2Model.fromDirectory` implementation.
- No network access is required at test time; the check is path-based.
- Existing Qwen, Confucius, Mega-ASR, Whisper, and LLM behavior must not change.

## Acceptance criteria

- `ModelCatalog.asrRequiredFiles(for: "mlx-community/FireRedASR2-AED-mlx")`
  equals `["config.json", "cmvn.json", "dict.txt", "model.safetensors"]` and no
  longer references the nonexistent `tokenizer.json`.
- `asrRepoContainsRequiredFiles` returns `false` when a required file (for
  example the safetensors weights) is absent and `true` for a directory holding
  the upstream manifest.
- A regression test fails on the previous list and passes on the corrected one.

## Open questions

None.
