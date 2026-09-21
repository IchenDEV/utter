# Spec: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `intent.md`

## Context

Three download paths share `ModelDownloadTasks` (a per-key dedupe gate) and
`DownloadProgressInfo`:

- Whisper: `WhisperKit.download` materializes into
  `<modelRoot>/models/argmaxinc/whisperkit-coreml/<variant>` and parks partials in
  `<repo>/.cache/huggingface/download/<file>.<etag>.incomplete`.
- LLM: `LLMModelFactory` fetches through the Swift Hub client; blobs are cached in
  the shared Hugging Face cache (`models--<ns>--<repo>/blobs/<etag>.incomplete`)
  and then copied into `<modelRoot>/models/<repo>`.
- ASR: `HubApi(downloadBase:).snapshot` uses the same Hub cache as LLM.

`refreshStatus` marks a model with bytes on disk but incomplete resources as
`.error(model.download_incomplete)`, and the row then offers Resume. `delete*`
removes only the materialized directory, so the shared partials outlive a delete.

`HubCache.default` resolves to `HF_HUB_CACHE` → `HF_HOME/hub` → the per-user
`~/.cache/huggingface/hub` (non-sandboxed) — outside `ModelStorage.root`.

## Design

`ModelDownloadRecovery` computes and removes partial markers:

- `partialArtifactURLs(kind:modelID:)` resolves the live layout;
  `incompleteArtifactURLs(kind:modelID:storageRoot:cacheRoots:)` is the pure seam
  tests use.
- Whisper scope: the `whisperkit-coreml` repository tree.
- LLM/ASR scope: the materialized repo plus `models--<ns>--<repo>` under each
  Hugging Face cache root.
- Only `*.incomplete` files are removed; completed files are untouched.

`ModelDownloadTasks` changes:

- `run` passes a per-run `token` to the operation.
- `isCurrent(key:token:)` guards every terminal status write, so a superseded or
  cancelled run cannot overwrite the state of its replacement.
- `cancel` now cancels **and forgets** the entry, so a retry starts immediately
  even if the transfer never observes cancellation.
- `ModelCatalog.cancelDownload` marks the model paused when it cancels an active
  run, restoring the Resume affordance.

`DownloadStallWatchdog` polls a last-activity timestamp and fires once after the
timeout. Each perform function creates one, feeds it progress from the download
callback, and stops it on completion. On stall it cancels the task and marks the
model with `model.download_failed_stalled`.

Each perform function purges stale markers when it starts from an `.error`
status (a user retry) and leaves a fresh download's resumable state alone.

## Safety and failure modes

- Deleting only `*.incomplete` files cannot destroy a usable model; a concurrent
  download for another model only restarts from zero.
- If a stalled transfer ignores cancellation, its task may linger, but it can no
  longer hold the key (the entry was dropped) and its writes are rejected by
  `isCurrent`.
- No network, permission, or privacy boundary changes. No new bundled resources.

## Test strategy

- `ModelDownloadRecoveryTests`: path layout, hidden `.cache` traversal, scoping to
  the whisper repo, materialized + shared cache coverage, missing-file tolerance.
- `ModelDownloadTasksTests`: dedupe, cancellation propagation, retry after a
  cancellation-ignoring transfer, `isCurrent` after cancel.
- `DownloadStallWatchdogTests`: fires on inactivity, stays quiet with progress.

## Rollout and rollback

Ships with the next Utter release. Rollback is reverting the commit; the change
only affects retry behavior and never mutates completed models, so a revert is
safe. Observation: a failed download followed by Resume should complete.
