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
  tree whose first variant component (or exact variant-prefixed flat cache name)
  names the requested variant. All variants share one repository and downloader
  versions have used both `<variant>/…` and flat cache entries, so retrying one
  variant must not remove another's partial.
- LLM/ASR scope: the materialized repo plus `models--<ns>--<repo>` under each
  Hugging Face cache root.
- Only `*.incomplete` files are removed; completed files are untouched.

`ModelDownloadTasks` changes:

- `run` passes a per-run `token` to the operation and keeps one slot per key.
- A duplicate request joins the in-flight run. A retry after `cancel` is
  **isolates the cancelled generation**: the live materialized repository and
  model-specific Hub cache roots are moved into a unique quarantine before the
  old entry is abandoned. The replacement can start immediately in fresh live
  paths, while the retired task remains tracked until its I/O returns. A
  duplicate that joined a run which then completes normally still does not
  restart it.
- `isCurrent(key:token:)` is false once a generation is abandoned, so a late
  transfer cannot write a terminal status over the replacement.
- Quarantine cleanup is deferred until every generation for the model has
  stopped writing. Completed files are merged back only when their live target
  is still absent; `.incomplete` markers are never restored.
- `ModelCatalog.cancelDownload` marks the model paused after isolating the old
  generation, restoring the Resume affordance. Delete waits for retired I/O
  before removing live files and partial markers.

Trade-off: if a library call never returns despite cancellation, retry remains
available because its paths are isolated, while delete waits for the retired
writer before performing destructive cleanup.

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
- Cancellation quarantine is temporary: completed files are restored into a
  still-missing live path after all retired I/O exits, while partial markers are
  discarded with the quarantine.
- If a stalled transfer ignores cancellation, its generation is quarantined and
  the retry uses fresh paths; its state writes are rejected by `isCurrent`.
- No network, permission, or privacy boundary changes. No new bundled resources.

## Test strategy

- `ModelDownloadRecoveryTests`: path layout, hidden `.cache` traversal,
  whisper-variant scoping (the retried variant's partial is removed while a
  sibling variant's is kept), materialized + shared cache coverage, missing-file
  tolerance.
- `ModelDownloadTasksTests`: dedupe, cancellation propagation, retry after a
  cancellation-ignoring transfer with a generation-isolation assertion,
  deferred cleanup, delete serialization, and `isCurrent` after abandon.
- `DownloadStallWatchdogTests`: fires on inactivity, stays quiet with progress,
  and the progress signal only advances on new bytes or fraction.

## Rollout and rollback

Ships with the next Utter release. Rollback is reverting the commit; the change
only affects retry behavior and never mutates completed models, so a revert is
safe. Observation: a failed download followed by Resume should complete.
