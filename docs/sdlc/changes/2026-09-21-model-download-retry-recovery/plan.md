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
- [x] Extend reclaim to every managed temporary artifact: `.utter-generations/*`,
      `.utter-promotion-*` candidates, `.utter-backup-*` copies, and
      `.utter-cleanup/*` retired roots.
- [x] Retire runtime cleanup in O(1) on the MainActor and delete detached, so a
      model-sized tree cannot block Cancel/Delete arbitration.
- [x] Re-check the generation token while cleanup is pending, so a Cancel/Delete
      during cleanup cannot let the old writer publish state.
- [x] Add regression tests for candidate preparation responsiveness, restart cleanup,
      and replacement failure rollback in `UtilityTests`.
- [x] Start the abnormal-exit startup sweep off the MainActor and gate all three
      public Catalog download entry points until that sweep completes.
- [x] Add a path-scoped `ModelCatalog` startup factory and enter/exit barrier
      so the real initializer wiring—not only the cleanup helper—has a
      MainActor responsiveness counterexample.
- [x] Add a dependency seam used only by tests so a real
      `ModelCatalog.downloadWhisper` Resume can overlap a suspended old writer.
- [ ] Re-run the final focused/full XCTest suites after the startup and Catalog
      facade additions; the three new XCTest cases raise the baseline counts by
      3. The rerun must include both startup wiring mutations.

## Verification plan

- [x] `bash scripts/ci-basic-checks.sh` on macOS: Pass ("Basic CI checks passed.")
- [x] `bash scripts/sdlc-checks.sh`: Pass ("SDLC checks passed.")
- [x] Baseline focused run on macOS at `3442f83641869f912247bef796e624efd813605a`: 50 tests passed across `ModelDownload|DownloadStallWatchdog|Utility`.
- [x] Baseline full suite at `3442f83641869f912247bef796e624efd813605a`: 667 XCTest = 653 passed + 14 skipped, 0 failures; one Swift Testing case also passed.
- [x] Baseline counterexamples at `3442f83641869f912247bef796e624efd813605a`: 34 tests passed across `ModelDownloadTasksTests|UtilityTests`.
- [ ] Final focused/full XCTest rerun at the continuation SHA: the new startup
      responsiveness, initializer wiring, and real Catalog Resume cases are
      expected to make these counts 53 focused / 37 counterexample / 670
      XCTest, subject to the raw log.
- [x] Release-style `bash scripts/build-app.sh --app-only` on macOS with Xcode Metal toolchain: Pass (assembled `dist/Utter.app`, compiled `default.metallib` [3.7 MB], ad-hoc signed with hardened runtime, release artifact verification passed).
- [x] Real interrupted-download retry on a networked machine (network disruption limited to test download sessions without cutting host network): tested on both WhisperKit (`openai_whisper-tiny`) and HubApi (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`):
      - WhisperKit: voluntary cancellation (`Task.cancel`) caught cleanly (`downloadError("已取消")`), Generation 2 resumed to 100%, atomic commit via prepared candidate publisher succeeded, model initialized, and real audio transcription verified on sample audio (`docs/assets/demos/en-sample.m4a` transcribed in 0.14s: `"Hey so I wanted to, I wanted to follow up on the design doc we talked about"`).
      - HubApi: voluntary cancellation caught cleanly, Generation 2 resumed to 100% downloading full model weights (`model.safetensors`, 278,064,920 bytes), atomic commit via prepared candidate publisher materialized symlinks into regular files in published directory, and `AutoTokenizer` round-trip encode/decode verified ("Hello world"). MLX ModelContainer loading and real text generation verified in host containing `default.metallib`: container loaded in 0.78s, text generated in 1.62s: `"Open source is a collaborative process of sharing code and data with the community for the benefit of everyone."`.
      - Interruption taxonomy: voluntary `Task.cancel` (`downloadError("已取消")`) vs transport connection failure (`downloadError("无法连接服务器。")`) verified.
      - Existing application resume path: `testApplicationModelCatalogResumePath` verified Catalog download -> cancelDownload -> awaited task settlement -> resume -> `.downloaded`; it does not cover overlap.
      - New in-flight Catalog facade counterexample is implemented as `testApplicationCatalogResumeEntryStartsBeforeOldDependencyReturns`; its macOS result is pending the final rerun.
- [ ] Startup-path mutation rerun: mutate the initializer to call synchronous
      `cleanupOrphanedGenerationStaging(storageRoot:)`, then mutate the helper
      task from detached to `Task { @MainActor in ... }`; each mutation must
      fail `testModelCatalogInitializerStartupCleanupKeepsMainActorResponsive`
      before restoring the exact continuation tree.
- [ ] Preserve the skip taxonomy in the final raw log: 4 live-download cases are
      gated by `OPENTYPE_LIVE_DOWNLOAD_INTEGRATION=1`; the other 10 baseline skips
      are ANE model (1), Apple Speech (1), template probe (1), foreground bundle
      identity (1), Espresso fallback (1), prompt dump (1), Qwen native ASR (2),
      and streaming ASR (2).
- [ ] Background I/O resource retention: cancelled transfers retain background Task and staging roots until dependency I/O returns; write safety is guaranteed via token isolation and publish rejection, but in-process network/staging resource contention when old I/O hangs permanently remains an R&D concern.

## Human gates

- Intent, spec, and verification approval before merge.
- The stall watchdog default (120 s) is a product-visible timeout; flag for the
  reviewer if a different threshold is preferred.
