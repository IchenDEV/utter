# Verification: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `git diff --check` | Pass | No whitespace errors in the recovery implementation or tests |
| Integration & P1 Promotion (`ModelStorage.swift`, `ModelCatalog*.swift`) | Pass | Added detached candidate preparation, rollback restoration on replacement failure, startup cleanup of orphaned generation roots |
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." on macOS |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `bash -n scripts/ci-basic-checks.sh scripts/sdlc-checks.sh` | Pass | Shell harness syntax is valid |
| Baseline full suite at `3442f83641869f912247bef796e624efd813605a` | Historical pass | 667 XCTest = 653 passed + 14 skipped, 0 failures; one Swift Testing case also passed. The 14 skips are not all live downloads: 4 are `OPENTYPE_LIVE_DOWNLOAD_INTEGRATION=1`, while 10 are ANE model (1), Apple Speech (1), template probe (1), foreground bundle identity (1), Espresso fallback (1), prompt dump (1), Qwen native ASR (2), and streaming ASR (2). |
| Baseline focused filter at `3442f83641869f912247bef796e624efd813605a` | Historical pass | 50 executed, 50 passed, 0 skipped, 0 failures across DownloadStallWatchdogTests (3), ModelDownloadFailureMessageTests (3), ModelDownloadRecoveryTests (10), ModelDownloadTasksTests (13), and UtilityTests (21). The earlier 48 figure is stale. |
| Final focused/full rerun after startup/Catalog P1 additions | Pending | Three new XCTest cases are present; expected counts are 53 in the broad focused filter, 37 in `ModelDownloadTasksTests|UtilityTests`, and 670 XCTest in the full suite, subject to the raw log. |
| Historical real network interrupted download → Resume → model load & inference (`OPENTYPE_LIVE_DOWNLOAD_INTEGRATION=1`) | Historical pass | WhisperKit audio transcription (`en-sample.m4a` in 0.14s) & HubApi 278MB safetensors download + ModelContainer load (0.78s) + real text generation (1.62s) pass with `default.metallib`; prior raw logs are attributed to `3442f83641869f912247bef796e624efd813605a` (the earlier metallib-only log to `522947265e83f07c730b00c2130db5c45727de55`), not the current continuation SHA. |

The focused tests retain the exact Whisper scope, sibling preservation,
flat-cache completion, duplicate retry deduplication, delete serialization, and
unchanged-progress coverage. This patch replaces the rejected quarantine-only
drain with `testCancelledGenerationCannotPublishAfterReplacement`: the old
writer retains its token-scoped staging root while a new generation publishes,
then its late commit is rejected. `UtilityTests` additionally verifies that a
Hub-style symlink is materialized as a regular readable file before its staging
cache is removed, that a replacement failure after candidate movement restores
the previous live model, that preparation leaves the MainActor responsive, and
that a restart cleanup removes all managed orphaned artifacts. The historical
baseline focused run has 50 passing tests; this continuation adds startup
scan/delete responsiveness, an initializer-wiring startup counterexample, and
a Catalog-facade Resume overlap test, which require a new macOS rerun.

The dependency path audit is reproducible from the pinned `Package.resolved`:

- `swift-huggingface` `b7219594`, `HubClient+Files.swift:520-522` computes the
  absolute `incompleteBlobPath` before network I/O and `:665-672` appends then
  moves/replaces it.
- `swift-transformers` `2fa33e1f`, `HubApi.swift:823-856` computes the
  absolute `incompleteDestination` before the async client download.

Those reads establish why a directory rename cannot be accepted as generation
isolation; the new file-level tests mirror the same original-URL behavior.

### Real Interrupted Download & Load Verification

Historical execution via `LiveDownloadVerificationTests` on macOS against live HuggingFace CDN, attributed to the source commits above; this is not exact-head evidence for the current continuation. Disruptions were strictly targeted to the test download tasks (without cutting host network):

1. **WhisperKit stack (`openai_whisper-tiny`, ~39 MB)**:
   - **Interruption**: Task 1 started downloading to generation staging root `staging1` (`.utter-generations/<token1>/download`). Mid-transfer interruption cancelled Task 1 via `Task.cancel()`, caught cleanly as `downloadError("已取消")`. `staging1` root remained preserved and isolated on disk with partial `.incomplete` files.
   - **Resume**: Generation 2 started with isolated token `staging2` (`.utter-generations/<token2>/download`). Resumed and completed all model components (AudioEncoder, MelSpectrogram, TextDecoder, config.json, generation_config.json, weight.bin) to 100%.
   - **Atomic commit**: Candidate materialized and rollback prepared via detached task `ModelStorage.prepareGenerationCommitOffMainActor`, then published atomically via `ModelStorage.publishPreparedGeneration` to `/Users/chenli/Library/Application Support/OpenType/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny`.
   - **Model loading**: Loaded via `WhisperKit(modelFolder:)`; model state initialized to `Loaded`.
   - **Real Audio Transcription**: Executed `whisperKit.transcribe(audioPath:)` on `docs/assets/demos/en-sample.m4a` in 0.14s, yielding exact spoken text: `"Hey so I wanted to, I wanted to follow up on the design doc we talked about"`.

2. **Hub-backed stack (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`, 278 MB)**:
   - **Interruption**: Task 1 initiated `HubApi.snapshot(matching: ["*.json"])` into `staging1` (`downloadBase` + `hubCache`). Mid-transfer interruption triggered `Task.cancel()`, caught cleanly as `downloadError("已取消")`. `staging1` root remained preserved on disk.
   - **Resume**: Generation 2 started with isolated token `staging2`. Resumed and downloaded all 11 model files including full `model.safetensors` (278,064,920 bytes) to 100% in 89.9s (foreground progress logged at 9% -> 27% -> 45% -> 54% -> 72% -> 81% -> 100%).
   - **Atomic commit & symlink materialization**: Candidate materialized and symlinks resolved via `ModelStorage.prepareGenerationCommitOffMainActor`, then published atomically via `ModelStorage.publishPreparedGeneration` to `/Users/chenli/Library/Application Support/OpenType/huggingface/models/mlx-community/Qwen2.5-0.5B-Instruct-4bit`. Verified `model.safetensors` is a regular file with exact size 278,064,920 bytes.
   - **Staging cleanup**: Generation staging root was removed; verified published files remain independent and readable.
   - **Tokenizer verification**: Loaded via `AutoTokenizer.from(modelFolder:)`; verified round-trip encode and decode ("Hello world").
   - **MLX Container Loading & Real Text Generation**: Built application Metal shader bundle (`mlx-swift_Cmlx.bundle` containing `default.metallib`, 3.7 MB) via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-app.sh --app-only`. With `default.metallib` available in the test runner host bundle resources, `LLMModelFactory.shared.loadContainer(from:using:)` loaded the published model container in **0.78s**. Real text generation via `ChatSession(container, instructions: "You are a helpful assistant.", generateParameters: GenerateParameters(maxTokens: 50, temperature: 0.3)).respond(to: "Hello! Tell me in one sentence what open source is.")` completed in **1.62s** with coherent response: `"Open source is a collaborative process of sharing code and data with the community for the benefit of everyone."`. Full weights download, atomic commit, ModelContainer loading, and text generation 100% verified.

3. **Interruption Taxonomy (`Task.cancel` vs Transport Fault)**:
   - `testTransportFailureVsTaskCancelTaxonomy` verified distinct error signatures:
     - `Task.cancel`: `downloadError("已取消")`
     - Transport failure (unreachable local socket `http://127.0.0.1:59999`): `downloadError("无法连接服务器。")`
   - Both pathways keep partial staging roots isolated in `.utter-generations/<uuid>/download` without corrupting published models.

4. **Application Catalog Resume Path**:
   - `testApplicationModelCatalogResumePath` verified the application-level lifecycle:
     - `ModelCatalog.shared.downloadWhisper("openai_whisper-tiny")` initiated.
     - `ModelCatalog.shared.cancelDownload` transitioned state to `.error("下载已暂停。点击“继续下载”可从现有文件接着下载")`.
     - Awaited download task settlement.
     - Resuming via `ModelCatalog.shared.downloadWhisper` resumed transfer, completed detached candidate preparation and atomic publication, and transitioned catalog status to `.downloaded`.
     - *Scope boundary*: this existing live test verifies graceful cancellation state transition and resumed completion after task settlement only; it is not evidence for concurrent in-flight writer overlap.
     - *New unit counterexample*: `testApplicationCatalogResumeEntryStartsBeforeOldDependencyReturns` now uses the public `ModelCatalog.downloadWhisper` entry twice with an injected suspended first dependency call. Its final macOS result is pending and must be recorded in the same exact-SHA raw log as the other P1 tests.

### Commit SHA Traceability

Each piece of evidence maps to its originating commit:
- `0167504b920de6b36cb36f1b8e703ce486d69e8f`: Baseline P0 implementation (generation token staging, watchdog, and initial 46 unit tests).
- `28a847f6018871f70210f119c4d650aed1e13040`: Live Whisper audio transcription (`en-sample.m4a`), full Hub 278 MB safetensors download, interruption taxonomy, application catalog resume path, and MLX metallib CLI constraint documentation.
- `6bcc5adc69c42f21aa905c05b74b6e041fc0b4c7`: Integration commit on PR #102 integrating detached candidate preparation, rollback restoration, and startup cleanup.
- `522947265e83f07c730b00c2130db5c45727de55`: Verified Hub MLX ModelContainer loading (0.78s) and real text generation (1.62s) with `default.metallib`, achieving complete end-to-end dual-stack live verification on macOS.
- `3442f83641869f912247bef796e624efd813605a`: historical macOS code/test run containing the managed-cleanup increment; its logs are not exact-head evidence for the later material-only `eb4c08a3` commit.
- `eb4c08a39b2104cbb1045fe0cd7eb589bd1c8e3f`: material baseline from which the startup and Catalog-facade P1 continuation is made; final evidence must use the new continuation SHA.

## Acceptance criteria

- Retry purges `.incomplete` markers — pass. `ModelDownloadRecoveryTests`
  covers hidden `.cache` traversal, whisper-variant scoping (a sibling variant's
  partial is preserved), and coverage of the materialized repo plus the shared
  Hub cache.
- Cancel makes the model resumable without sharing paths with the old transfer —
  **pass on macOS**: the three download stacks receive token-scoped roots;
  `testCancelledGenerationCannotPublishAfterReplacement` covers
  old-writer-never-returns/new-generation-completes/old-late-arrival;
  `testDuplicateJoinedBeforeCancelDoesNotRestart` and
  `testTwoConcurrentRetriesAfterCancelStartOnlyOneWriter` cover request
  ownership; `testDeleteArbitratesAgainstLateCancelledWriter` covers Delete
  publication arbitration.
- Stalled download detection — **pass on macOS**. `DownloadStallWatchdogTests`
  fires on inactivity and stays quiet while progress arrives; the
  progress-signal test rejects unchanged callbacks, and `isCurrent` prevents
  late state writes.
- Delete removes partial markers — implemented in `deleteWhisper`,
  `deleteLLM`, and `deleteASR`; covered indirectly by the recovery path tests.
- Prepared publication responsiveness — **pass on macOS**: candidate and rollback
  preparation run in detached tasks (`prepareGenerationCommitOffMainActor`); only
  token validation and same-volume replacement run in MainActor arbitration.
  Verified by `testGenerationPreparationKeepsMainActorResponsive`.
- Replacement failure rollback — **pass on macOS**: if candidate replacement
  fails after file operations begin, `publishPreparedGeneration` cleans up the
  corrupted candidate and restores the previous live model from backup. Verified
  by `testFailedCommitKeepsThePreviouslyPublishedModel`.
- Restart cleanup — **pass on macOS**: `ModelCatalog.init` reclaims every
  managed artifact left by abnormal process termination — generation roots,
  `.utter-promotion-*` candidates, `.utter-backup-*` rollback copies, and
  `.utter-cleanup/*` retired roots — before starting fresh downloads. Verified by
  `testStartupCleanupRemovesAllOrphanedGenerationArtifacts` (asserts all five
  directories are removed) and confirmed by mutation: disabling the
  promotion/backup scan makes it fail (3 vs 5 removed, leftovers remain).
- Startup scan/delete responsiveness — **pending final macOS rerun**:
  `testStartupCleanupKeepsMainActorResponsive` exercises the same background
  startup sweep with a model-sized orphan tree and must fail if recursive
  scan/delete is moved back onto the MainActor. The initializer-level
  `testModelCatalogInitializerStartupCleanupKeepsMainActorResponsive` injects
  the production path-scoped helper through `ModelCatalog.init`, holds an
  entered/not-exited barrier, and requires a MainActor heartbeat between those
  barriers. Its independent detached timeout releases the gate on failure.
  Two planned mutations must fail this test: synchronous initializer wiring and
  replacing `Task.detached` with `Task { @MainActor in ... }`.
- Runtime cleanup responsiveness — **pass on macOS**: retiring a staged or
  superseded tree moves it into the managed cleanup root in O(1) on the
  MainActor and deletes it in a detached task, so a model-sized copy never
  blocks Cancel/Delete arbitration. Verified by
  `testGenerationCleanupKeepsMainActorResponsive`.
- Application-layer Resume before the old writer returns — **pending final
  macOS rerun**: `testApplicationCatalogResumeEntryStartsBeforeOldDependencyReturns`
  drives both generations through `ModelCatalog.downloadWhisper`, cancels while
  the first dependency call is suspended, and asserts the replacement enters
  before the old dependency is released. The older
  `testApplicationCancelAllowsResumeBeforeOldWriterReturns` remains an
  arbitration-level test, not the application-entry proof.
- `swift test` execution — **historical baseline only** at `3442f83641869f912247bef796e624efd813605a`: the
  `ModelDownloadTasksTests|UtilityTests` run is 34 executed, 0 failures; the
  full suite is 667 XCTest with 14 skips and 0 failures. Final P1 counts are
  pending a rerun at the new continuation SHA and must not be inferred from the
  baseline.
- Real network interrupted download → Resume → model load & inference — **pass on macOS**:
  WhisperKit end-to-end download, resume, model load, and real audio transcription pass 100% (`en-sample.m4a` in 0.14s).
  HubApi full weights download (278 MB safetensors), symlink materialization, staging purge, tokenizer encode/decode, MLX ModelContainer loading (0.78s), and real text generation (1.62s) pass 100% in test host with `default.metallib`.
  Interruption taxonomy (`Task.cancel` vs transport fault) and the settled-task
  application `ModelCatalog` resume path pass within that recorded scope; the
  in-flight Catalog facade counterexample is tracked separately below.

### Startup wiring mutation commands

Run these from the fixed continuation checkout, one at a time, and restore the
file from the saved copy after each command. Both mutations are expected to
make the initializer-level test exit non-zero; the unmutated test must pass.

```sh
cp Sources/Config/ModelCatalog.swift "$TMPDIR/ModelCatalog.swift.p3-orig"
perl -0pi -e 's/startupCleanupTask = startupCleanup\(startupStorageRoot\)/let cleanupCount = ModelStorage.cleanupOrphanedGenerationStaging(storageRoot: startupStorageRoot)\n        startupCleanupTask = Task { cleanupCount }/' Sources/Config/ModelCatalog.swift
swift test --filter 'UtilityTests/testModelCatalogInitializerStartupCleanupKeepsMainActorResponsive'
cp "$TMPDIR/ModelCatalog.swift.p3-orig" Sources/Config/ModelCatalog.swift

cp Sources/Config/ModelStorage.swift "$TMPDIR/ModelStorage.swift.p3-orig"
perl -0pi -e 's/Task\.detached\(priority: \.utility\) \{/Task { @MainActor in/' Sources/Config/ModelStorage.swift
swift test --filter 'UtilityTests/testModelCatalogInitializerStartupCleanupKeepsMainActorResponsive'
cp "$TMPDIR/ModelStorage.swift.p3-orig" Sources/Config/ModelStorage.swift
```

The test's detached timeout calls `StartupCleanupGate.release()` independently
of MainActor scheduling, so either a missing initializer factory call or a
MainActor child task cannot leave the test permanently blocked. The exact
mutation output and exit codes remain pending the macOS rerun.

## Residual risk

- Write safety is guaranteed by token-scoped isolation and atomic commit rejection; Cancelled downloads immediately start new generations without waiting for old writers to exit.
- Cancelled transfers retain background Task and staging roots until underlying URLSession/I/O returns; in-process background network/staging resource contention when old I/O hangs permanently remains an R&D concern.
- The 120 s stall threshold is a judgment call; a very slow link with no progress reports for over two minutes is marked paused and resumable.
- External CI and PR merge gate remain subject to runner completion and human review approval.

## Decision

The baseline implementation and live evidence pass within their recorded scope,
but this continuation is not ready for final acceptance until macOS reruns the
two new P1 counterexamples. The final raw log must contain one complete
continuation SHA, each exact command, environment gates, and the real exit code;
prior logs remain historical evidence at their recorded source commit rather
than proof for `eb4c08a3` or its continuation.
