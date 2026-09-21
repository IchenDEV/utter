# Plan: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `spec.md`

## Work items

- [x] Add `ModelDownloadRecovery` with the pure path seam and marker cleanup.
- [x] Add Hugging Face cache-root resolution to `ModelStorage`.
- [x] Give `ModelDownloadTasks` a run token, `isCurrent`, and forgetting cancel.
- [x] Purge stale markers on retry; keep resume for a fresh download.
- [x] Make `cancelDownload` immediately mark the model paused.
- [x] Add `DownloadStallWatchdog` and wire it into all three download paths.
- [x] Purge partial markers when deleting a model.
- [x] Add `model.download_failed_stalled` to both localizations.
- [x] Add unit tests for recovery, the retry gate, and the watchdog.
- [x] Keep one writer per model: a retry waits for a cancelled transfer to exit.
- [x] Scope Whisper partial cleanup to the requested variant.
- [x] Treat only real byte/fraction growth as download progress.

## Verification plan

- [x] `bash scripts/ci-basic-checks.sh`
- [x] `bash scripts/sdlc-checks.sh`
- [x] `swift test` (full suite)
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
