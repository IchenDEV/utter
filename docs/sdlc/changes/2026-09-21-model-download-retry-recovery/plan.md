# Plan: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `spec.md`

## Work items

- [x] Add `ModelDownloadRecovery` with the pure path seam and marker cleanup.
- [x] Add Hugging Face cache-root resolution to `ModelStorage`.
- [x] Give `ModelDownloadTasks` a run token, `isCurrent`, and cancellation-aware
      single-writer draining.
- [x] Purge stale markers on retry; keep resume for a fresh download.
- [x] Make `cancelDownload` immediately mark the model paused.
- [x] Add `DownloadStallWatchdog` and wire it into all three download paths.
- [x] Purge partial markers when deleting a model.
- [x] Add `model.download_failed_stalled` to both localizations.
- [x] Add unit tests for recovery, the retry gate, and the watchdog.
- [x] Keep one live writer per model; hold the cancelled generation's slot until
      dependency I/O returns before admitting a retry.
- [x] Scope Whisper partial cleanup to the requested variant.
- [x] Treat only real byte/fraction growth as download progress.

## Verification plan

- [ ] `bash scripts/ci-basic-checks.sh` (requires the macOS Swift toolchain)
- [x] `bash scripts/sdlc-checks.sh`
- [ ] `swift test` (full suite; requires the macOS Swift toolchain)
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
