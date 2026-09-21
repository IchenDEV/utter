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
- Whisper scope: `*.incomplete` files under the `whisperkit-coreml` repository
  tree whose path names the requested variant. All variants share one repository
  and the downloader keeps partials under `<variant>/…` inside its `.cache`
  tree, so retrying one variant must not remove another's partial.
- LLM/ASR scope: the materialized repo plus `models--<ns>--<repo>` under each
  Hugging Face cache root.
- Only `*.incomplete` files are removed; completed files are untouched.

`ModelDownloadTasks` changes:

- `run` passes a per-run `token` to the operation and keeps one slot per key.
- A duplicate request joins the in-flight run. A retry after `cancel` is
  **serialized behind the cancelled run**: the entry is retained (marked
  cancelled) until the old operation actually returns, so the old transfer and
  its replacement can never touch the same cache paths concurrently. A duplicate
  that joined a run which then completes normally still does not restart it.
- `isCurrent(key:token:)` is false for a cancelled entry, so a cancelled run
  cannot write a terminal status.
- `ModelCatalog.cancelDownload` marks the model paused when it cancels an active
  run, restoring the Resume affordance.

Trade-off: if a library call never returns despite cancellation, the retry waits
for it rather than racing it. Correctness on disk wins over a hypothetical hung
transfer; the UI already offers Resume because the status was set to paused.

`DownloadStallWatchdog` polls a last-activity timestamp and fires once after the
timeout. A shared `DownloadProgressSignal` only calls `noteProgress()` when the
reported bytes or fraction actually increase, so a downloader that keeps firing
its callback with an unchanged value still stalls. Each perform function creates
the watchdog and signal, and stops the watchdog on completion. On stall it
cancels the task and marks the model with `model.download_failed_stalled`.

Each perform function purges stale markers when it starts from an `.error`
status (a user retry) and leaves a fresh download's resumable state alone.

## Safety and failure modes

- Deleting only `*.incomplete` files, scoped to the requested model, cannot
  destroy a usable model or another model's in-flight partial.
- If a stalled transfer ignores cancellation, the retry waits for it instead of
  racing it on disk; its state writes are rejected by `isCurrent`.
- No network, permission, or privacy boundary changes. No new bundled resources.

## Test strategy

- `ModelDownloadRecoveryTests`: path layout, hidden `.cache` traversal,
  whisper-variant scoping (the retried variant's partial is removed while a
  sibling variant's is kept), materialized + shared cache coverage, missing-file
  tolerance.
- `ModelDownloadTasksTests`: dedupe, cancellation propagation, retry after a
  cancellation-ignoring transfer with a concurrency assertion that the
  cancelled writer has fully exited before the retry starts, `isCurrent` after
  cancel.
- `DownloadStallWatchdogTests`: fires on inactivity, stays quiet with progress,
  and the progress signal only advances on new bytes or fraction.

## Rollout and rollback

Ships with the next Utter release. Rollback is reverting the commit; the change
only affects retry behavior and never mutates completed models, so a revert is
safe. Observation: a failed download followed by Resume should complete.
