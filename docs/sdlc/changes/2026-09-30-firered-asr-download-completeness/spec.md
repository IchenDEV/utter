# Spec: Fix FireRedASR2 (小红书) model download completeness

**Status:** approved
**Approved-by:** chenli (explicit confirmation in this chat)
**Approved-date:** 2026-09-30
**Upstream:** docs/sdlc/changes/2026-09-30-firered-asr-download-completeness/intent.md
**Risk:** medium — model/runtime behavior

## Context

ASR downloads for the generic MLX STT models run through
`ModelCatalog.downloadASR` -> `performASRDownload` -> `HubApi.snapshot`. When the
transfer returns, `asrRepoIsComplete` calls
`asrRepoContainsRequiredFiles(repositoryID, at:)`, which requires every path in
`asrRequiredFiles(for:)` to exist with a nonzero size. The same list gates
`MLXSTTEngine.checkModelReady` and therefore whether the engine is considered
usable.

The upstream `mlx-community/FireRedASR2-AED-mlx` repository manifest (verified
via the Hugging Face tree API) is: `.gitattributes`, `cmvn.json`, `config.json`,
`dict.txt`, `model.safetensors`, `train_bpe1000.model`. The catalog listed
`tokenizer.json`, which is absent.

The pinned `mlx-audio-swift` 0.1.3 `FireRedASR2Model` confirms the runtime
requirements:

- `fromDirectory` throws if `config.json` is missing and loads every
  `*.safetensors` file in the directory to build weights.
- `loadAssets(from:)` reads `cmvn.json` for CMVN statistics and constructs the
  tokenizer from `dict.txt`; the tokenizer is required to decode output.

`train_bpe1000.model` is only used by the Python reference and is not read by
the Swift runtime, so it is not required.

## Design

Change only the FireRed case of `ModelCatalog.asrRequiredFiles`:

```swift
case "mlx-community/FireRedASR2-AED-mlx":
    return ["config.json", "cmvn.json", "dict.txt", "model.safetensors"]
```

No interfaces, state, or data flow change. The check remains path-based and
model-scoped, so recovery, retry, and readiness continue to use the same code
paths with a corrected manifest.

Non-goals: the download transport, staging/publish machinery, and the other
model entries are untouched. `Mega-ASR-6bit`'s existing list is left as-is; its
referenced files exist upstream.

## Safety and failure modes

- Under-counting required files could mark a broken download complete. The list
  includes the safetensors weights, `cmvn.json`, and `dict.txt`, which are the
  files the runtime needs; a missing weight or asset keeps the status as
  incomplete and the retry path can recover.
- No privacy, security, or network-boundary change is introduced.
- Rollback is a single-line revert; no stored data is migrated.

## Test strategy

- A unit test asserts the exact required list and that it no longer contains
  `tokenizer.json`.
- The same test drives `asrRepoContainsRequiredFiles` over a temporary directory
  holding the upstream manifest, asserting `false` before the weights are
  present and `true` after.
- Full `swift test` and repository checks confirm no other model regressed.

## Rollout and rollback

Ship in a normal app release. Observation: after downloading FireRedASR2-AED the
status becomes `.downloaded` and the engine reports ready. Rollback: revert the
required-file list if a runtime asset turns out to differ.
