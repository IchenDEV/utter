# Verification: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `git diff --check` | Pass | No whitespace errors in the recovery implementation or tests |
| Integration fix (`ModelStorage.swift`) | Pass | Added `import HuggingFace` in `ModelStorage.swift` so `HubCache` resolves properly in the target; resolved type inference in `ModelCatalogASR.swift` |
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." on macOS |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `bash -n scripts/ci-basic-checks.sh scripts/sdlc-checks.sh` | Pass | Shell harness syntax is valid |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native` (full suite) | Pass | 661 XCTest executed, 12 skipped, 0 failures; 1 swift-testing passed (total 662 executed, 12 skipped, 0 failures) on macOS |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native --filter "ModelDownload\|DownloadStallWatchdog\|Utility"` | Pass | 46 executed, 0 failures across DownloadStallWatchdogTests (3), ModelDownloadFailureMessageTests (3), ModelDownloadRecoveryTests (10), ModelDownloadTasksTests (12), and UtilityTests (18) on macOS |
| Real network interrupted download → Resume → model load / transcription (`OPENTYPE_LIVE_DOWNLOAD_INTEGRATION=1`) | Partial / Documented | WhisperKit full transcription (`en-sample.m4a` in 0.11s) & HubApi 278MB safetensors download + AutoTokenizer pass; MLX container loading requires Xcode app bundle metallib |

The focused tests retain the exact Whisper scope, sibling preservation,
flat-cache completion, duplicate retry deduplication, delete serialization, and
unchanged-progress coverage. This patch replaces the rejected quarantine-only
drain with `testCancelledGenerationCannotPublishAfterReplacement`: the old
writer retains its token-scoped staging root while a new generation publishes,
then its late commit is rejected. `UtilityTests` additionally verifies that a
Hub-style symlink is materialized as a regular readable file before its staging
cache is removed, and that a broken staged tree leaves the previous live model
unchanged. All 46 focused tests pass on macOS.

The dependency path audit is reproducible from the pinned `Package.resolved`:

- `swift-huggingface` `b7219594`, `HubClient+Files.swift:520-522` computes the
  absolute `incompleteBlobPath` before network I/O and `:665-672` appends then
  moves/replaces it.
- `swift-transformers` `2fa33e1f`, `HubApi.swift:823-856` computes the
  absolute `incompleteDestination` before the async client download.

Those reads establish why a directory rename cannot be accepted as generation
isolation; the new file-level tests mirror the same original-URL behavior.

### Real Interrupted Download & Load Verification

Tested via `LiveDownloadVerificationTests` on macOS against live HuggingFace CDN with disruptions strictly targeted to the test download tasks (without cutting host network):

1. **WhisperKit stack (`openai_whisper-tiny`, ~39 MB)**:
   - **Interruption**: Task 1 started downloading to generation staging root `staging1` (`.utter-generations/<token1>/download`). Mid-transfer interruption cancelled Task 1 via `Task.cancel()`, caught cleanly as `downloadError("已取消")`. `staging1` root remained preserved and isolated on disk with partial `.incomplete` files.
   - **Resume**: Generation 2 started with isolated token `staging2` (`.utter-generations/<token2>/download`). Resumed and completed all model components (AudioEncoder, MelSpectrogram, TextDecoder, config.json, generation_config.json, weight.bin) to 100%.
   - **Atomic commit**: `ModelStorage.commitGeneration` committed `staging2` to `/Users/chenli/Library/Application Support/OpenType/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny`.
   - **Model loading**: Loaded via `WhisperKit(modelFolder:)`; model state initialized to `Loaded`.
   - **Real Audio Transcription**: Executed `whisperKit.transcribe(audioPath:)` on `docs/assets/demos/en-sample.m4a` in 0.11s, yielding exact spoken text: `"Hey so I wanted to, I wanted to follow up on the design doc we talked about"`.

2. **Hub-backed stack (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`, 278 MB)**:
   - **Interruption**: Task 1 initiated `HubApi.snapshot(matching: ["*.json"])` into `staging1` (`downloadBase` + `hubCache`). Mid-transfer interruption triggered `Task.cancel()`, caught cleanly as `downloadError("已取消")`. `staging1` root remained preserved on disk.
   - **Resume**: Generation 2 started with isolated token `staging2`. Resumed and downloaded all 11 model files including full `model.safetensors` (278,064,920 bytes) to 100% in 80.9s (foreground progress logged at 9% -> 36% -> 45% -> 54% -> 81% -> 100%).
   - **Atomic commit & symlink materialization**: `ModelStorage.commitGeneration` materialized symlinks as regular files into `/Users/chenli/Library/Application Support/OpenType/huggingface/models/mlx-community/Qwen2.5-0.5B-Instruct-4bit`. Verified `model.safetensors` is a regular file with exact size 278,064,920 bytes.
   - **Staging cleanup**: Generation staging root was removed; verified published files remain independent and readable.
   - **Tokenizer verification**: Loaded via `AutoTokenizer.from(modelFolder:)`; verified round-trip encode and decode ("Hello world").
   - **MLX Container Loading & Inference Scope**: In the SwiftPM CLI test runner (`swift test`), `LLMModelFactory.shared.loadContainer` invokes MLX C++ stream initialization which fails with `std::runtime_error: Failed to load the default metallib` because Metal kernels (`default.metallib`) are only compiled into resource bundles during Xcode application packaging (`scripts/build-app.sh:5-7`). Therefore, container loading and real text generation are documented as uncompleted in the CLI test runner environment.

3. **Interruption Taxonomy (`Task.cancel` vs Transport Fault)**:
   - `testTransportFailureVsTaskCancelTaxonomy` verified distinct error signatures:
     - `Task.cancel`: `downloadError("已取消")`
     - Transport failure (unreachable local socket `http://127.0.0.1:59999`): `downloadError("无法连接服务器。")`
   - Both pathways keep partial staging roots isolated in `.utter-generations/<uuid>/download` without corrupting published models.

4. **Application Catalog Resume Path**:
   - `testApplicationModelCatalogResumePath` verified the application-level lifecycle:
     - `ModelCatalog.shared.downloadWhisper("openai_whisper-tiny")` initiated.
     - `ModelCatalog.shared.cancelDownload` transitioned state to `.error("下载已暂停。点击“继续下载”可从现有文件接着下载")`.
     - Resuming via `ModelCatalog.shared.downloadWhisper` resumed transfer, completed atomic commit, and transitioned catalog status to `.downloaded`.

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
- `swift test` execution — **pass on macOS**: 46 focused tests pass (0 failures);
  full suite passes with 661 XCTest executed, 12 skipped, 0 failures, plus 1
  swift-testing test.
- Real network interrupted download → Resume → model load — **partially verified with scope boundary on macOS**:
  WhisperKit end-to-end download, resume, model load, and real audio transcription pass 100%. HubApi full weights download (278 MB safetensors), symlink materialization, staging purge, and tokenizer encode/decode pass 100%. MLX container loading and text generation remain uncompleted due to Xcode metallib bundling requirement.
  Interruption taxonomy (`Task.cancel` vs transport fault) and application `ModelCatalog` resume path pass 100%.

## Residual risk

- MLX container loading and LLM text generation require precompiled `default.metallib` from `xcodebuild` app bundle packaging, which cannot run in `swift test` CLI test runner; verified scope covers full weights (278 MB) download, symlink materialization, staging isolation, and AutoTokenizer.
- The 120 s stall threshold is a judgment call; a very slow link with no progress
  reports for over two minutes would be failed and marked resumable.
- A transfer that ignores cancellation remains in its generation root until it
  returns; it can no longer affect model state or share a live path with a
  replacement. A long-lived retired task can retain disk space temporarily.

## Decision

Implementation and verification are complete on macOS within the verified scope. Acceptance criteria, real audio transcription on Whisper, full 278 MB weights download, tokenizer verification, interruption taxonomy, and ModelCatalog resume pass. Ready for review.
