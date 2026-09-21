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
- [x] Run candidate materialization and rollback backup preparation in a detached
      task (`prepareGenerationCommitOffMainActor`) so MainActor remains responsive.
- [x] Add replacement failure rollback in `publishPreparedGeneration` restoring
      the previous model from backup when replacement fails.
- [x] Add startup cleanup (`cleanupOrphanedGenerationStaging`) in `ModelCatalog`
      reclaiming orphaned generation roots from previous abnormal process exits.
- [x] Add regression tests for candidate preparation responsiveness, restart cleanup,
      and replacement failure rollback in `UtilityTests`.

## Verification plan

- [x] `bash scripts/ci-basic-checks.sh` on macOS: Pass ("Basic CI checks passed.")
- [x] `bash scripts/sdlc-checks.sh`: Pass ("SDLC checks passed.")
- [x] `swift test` on macOS for focused tests: Pass (48 executed, 0 failures across `ModelDownload|DownloadStallWatchdog|Utility`)
- [x] `swift test` on macOS for full suite: Pass (665 XCTest executed, 14 skipped, 0 failures, plus 1 swift-testing test)
- [x] Release-style `bash scripts/build-app.sh --app-only` on macOS with Xcode Metal toolchain: Pass (assembled `dist/Utter.app`, compiled `default.metallib` [3.7 MB], ad-hoc signed with hardened runtime, release artifact verification passed).
- [x] Real interrupted-download retry on a networked machine (network disruption limited to test download sessions without cutting host network): tested on both WhisperKit (`openai_whisper-tiny`) and HubApi (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`):
      - WhisperKit: voluntary cancellation (`Task.cancel`) caught cleanly (`downloadError("已取消")`), Generation 2 resumed to 100%, atomic commit via prepared candidate publisher succeeded, model initialized, and real audio transcription verified on sample audio (`docs/assets/demos/en-sample.m4a` transcribed in 0.10s: `"Hey so I wanted to, I wanted to follow up on the design doc we talked about"`).
      - HubApi: voluntary cancellation caught cleanly, Generation 2 resumed to 100% downloading full model weights (`model.safetensors`, 278,064,920 bytes), atomic commit via prepared candidate publisher materialized symlinks into regular files in published directory, and `AutoTokenizer` round-trip encode/decode verified ("Hello world"). MLX ModelContainer loading and real text generation verified in host containing `default.metallib`: container loaded in 0.78s, text generated in 1.62s: `"Open source is a collaborative process of sharing code and data with the community for the benefit of everyone."`.
      - Interruption taxonomy: voluntary `Task.cancel` (`downloadError("已取消")`) vs transport connection failure (`downloadError("无法连接服务器。")`) verified.
      - Application resume path: `ModelCatalog` download -> pause/cancel -> resume -> `.downloaded` verified.
- [ ] Permanent hang recovery: waiting for old I/O exit addresses write safety, but recovery when old I/O hangs permanently remains unproven (marked as R&D blocker).

## Human gates

- Intent, spec, and verification approval before merge.
- The stall watchdog default (120 s) is a product-visible timeout; flag for the
  reviewer if a different threshold is preferred.
