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

The locked dependencies make live-path ownership stricter than a directory
rename suggests. `swift-huggingface` 0.9.0
(`b721959445b617d0bf03910b2b4aced345fd93bf`) computes
`incompleteBlobPath` before its network await and later appends/replaces that
same absolute URL. `swift-transformers` 1.3.3
(`2fa33e1f5e7131a7fc64c28e6d161dcec0d24820`) likewise computes
`incompleteDestination` before its async client download. A cancelled
continuation can therefore reopen the original live path after a directory has
been moved; quarantine alone is not a valid writer-isolation proof.

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
- A duplicate request joins the in-flight run. `cancel` marks the current entry
  cancelled but deliberately retains its slot until the dependency operation
  returns. A Resume request that arrived during that drain claims one restart;
  concurrent Resume requests join that replacement. A duplicate that joined a
  run which completes normally still does not restart it.
- `isCurrent(key:token:)` becomes false as soon as cancellation is requested,
  preventing late progress or terminal state from reaching the UI, while the
  entry remains active for disk serialization.
- `ModelCatalog.cancelDownload` marks the model paused and restores Resume,
  but the next download reuses live paths only after the old absolute-path I/O
  has returned. Delete uses the same per-key gate.

Trade-off: if a library call never returns despite cancellation, retry remains
visible but waits for that dependency call to drain. This is fail-closed: a
retry cannot share a path with a writer that may still reopen the original
absolute URL.

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
- Cancellation keeps the live paths owned by the cancelled task until its I/O
  returns; no directory move is treated as isolation. The next generation then
  purges only the requested model's `.incomplete` markers.
- If a stalled transfer ignores cancellation, its Resume action remains
  serialized behind that task; its state writes are rejected by `isCurrent`.
- No network, permission, or privacy boundary changes. No new bundled resources.

## Test strategy

- `ModelDownloadRecoveryTests`: path layout, hidden `.cache` traversal,
  whisper-variant scoping (the retried variant's partial is removed while a
  sibling variant's is kept), materialized + shared cache coverage, missing-file
  tolerance.
- `ModelDownloadTasksTests`: dedupe, cancellation propagation, retry after a
  cancellation-ignoring transfer that writes the original live URL after
  cancellation, single replacement ownership for concurrent Resume requests,
  delete serialization, and `isCurrent` after cancellation.
- `DownloadStallWatchdogTests`: fires on inactivity, stays quiet with progress,
  and the progress signal only advances on new bytes or fraction.

## Rollout and rollback

Ships with the next Utter release. Rollback is reverting the commit; the change
only affects retry behavior and never mutates completed models, so a revert is
safe. Observation: a failed download followed by Resume should complete.
