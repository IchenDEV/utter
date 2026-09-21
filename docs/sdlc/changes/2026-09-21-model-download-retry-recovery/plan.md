# Plan: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `spec.md`

## Work items

- [x] Add `ModelDownloadRecovery` with the pure path seam and marker cleanup.
- [x] Add Hugging Face cache-root resolution to `ModelStorage`.
- [x] Give `ModelDownloadTasks` a run token, `isCurrent`, and cancellation-aware
      retired-writer retention/publication arbitration.
- [x] Purge stale markers on retry; keep resume for a fresh download.
- [x] Make `cancelDownload` immediately mark the model paused.
- [x] Add `DownloadStallWatchdog` and wire it into all three download paths.
- [x] Purge partial markers when deleting a model.
- [x] Add `model.download_failed_stalled` to both localizations.
- [x] Add unit tests for recovery, the retry gate, and the watchdog.
- [x] Keep one current publisher per model; retain a cancelled generation's
      task/root until dependency I/O returns while admitting an isolated retry.
- [x] Scope Whisper partial cleanup to the requested variant.
- [x] Treat only real byte/fraction growth as download progress.
- [x] Inject a token-scoped staging `downloadBase` and Hub cache into Whisper,
      LLM, and ASR download creation.
- [x] Materialize Hub symlinks and atomically promote complete staged models,
      preserving the previous model on commit failure.
- [x] Serialize token validation, publication, Cancel, and Delete on the
      MainActor while retaining retired writer staging until operation return.
- [x] Add the old-writer-never-returns/new-generation-late-arrival regression
      and staging cleanup/readability tests.

## Verification plan

- [ ] `bash scripts/ci-basic-checks.sh` on macOS (exact `4fc4ee4` baseline
      passed; current Linux image has no Swift toolchain)
- [x] `bash scripts/sdlc-checks.sh`
- [ ] `swift test` on macOS for this P0 patch (the exact `4fc4ee4` baseline
      passed before this patch; current Linux image has no Swift toolchain)
- [ ] Release-style `bash scripts/build-app.sh` on a machine with the Metal
      toolchain (CI `SDLC Gate`), not available in this environment.
- [ ] Real interrupted-download retry on a networked machine. Recipe: start a
      model download and cut the network mid-transfer; confirm the row shows a
      failure, press Resume, and confirm the download completes and the model
      then loads (Settings → Models → Use / a dictation round-trip).

## Human gates

- Intent, spec, and verification approval before merge.
- The stall watchdog default (120 s) is a product-visible timeout; flag for the
  reviewer if a different threshold is preferred.
