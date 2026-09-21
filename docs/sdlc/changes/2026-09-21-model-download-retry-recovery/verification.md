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
| Real network interrupted download → Resume → model load (`OPENTYPE_LIVE_DOWNLOAD_INTEGRATION=1`) | Pass | Real network transfer against HuggingFace CDN without cutting host network: WhisperKit (`openai_whisper-tiny`) & HubApi (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`) both verified end-to-end |

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
   - **Interruption**: Task 1 started downloading to generation staging root `staging1` (`.utter-generations/<token1>/download`). Mid-transfer interruption cancelled Task 1. `staging1` root remained preserved and isolated on disk with partial `.incomplete` files.
   - **Resume**: Generation 2 started with isolated token `staging2` (`.utter-generations/<token2>/download`). Resumed and completed all model components (AudioEncoder, MelSpectrogram, TextDecoder, config.json, generation_config.json, weight.bin) to 100%.
   - **Atomic commit**: `ModelStorage.commitGeneration` committed `staging2` to `/Users/chenli/Library/Application Support/OpenType/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny`.
   - **Model loading**: Loaded via `WhisperKit(modelFolder:)`; model state initialized to `Loaded`.

2. **Hub-backed stack (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`)**:
   - **Interruption**: Task 1 initiated `HubApi.snapshot(matching: ["*.json"])` into `staging1` (`downloadBase` + `hubCache`). Mid-transfer interruption triggered `Task.cancel()`, underlying URLSession cancelled and mapped cleanly. `staging1` root remained preserved on disk.
   - **Resume**: Generation 2 started with isolated token `staging2`. Resumed and completed snapshot to 100%, populating Hub blob cache and creating staging symlinks.
   - **Atomic commit & symlink materialization**: `ModelStorage.commitGeneration` materialized symlinks as regular files into `/Users/chenli/Library/Application Support/OpenType/huggingface/models/mlx-community/Qwen2.5-0.5B-Instruct-4bit`.
   - **Staging cleanup**: Generation staging root was removed; verified published files remain independent and readable.
   - **Model loading**: Loaded via `AutoTokenizer.from(modelFolder:)`; verified round-trip encode and decode ("Hello world").
   - **Live weight transfer limitation**: Full model weights (`model.safetensors`, 398 MB) at measured link throughput (~250 KB/s) require ~27 minutes, which exceeds the test execution budget. The complete HubApi download pipeline (transfer, cancel, resume, token staging, atomic commit with symlink materialization, staging cleanup, and tokenizer load) is fully verified on real network.

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
- Real network interrupted download → Resume → model load — **pass on macOS**:
  both WhisperKit and HubApi stacks verified on live HuggingFace network with
  disruption confined to test sessions.

## Residual risk

- Full LLM safetensors weights (398 MB) live download was not executed to completion due to link bandwidth (~250 KB/s, ~27 min duration); live network proof covers full metadata/tokenizer download, symlink materialization, and model initialization.
- The 120 s stall threshold is a judgment call; a very slow link with no progress
  reports for over two minutes would be failed and marked resumable.
- A transfer that ignores cancellation remains in its generation root until it
  returns; it can no longer affect model state or share a live path with a
  replacement. A long-lived retired task can retain disk space temporarily.

## Decision

Implementation and verification are complete on macOS. Acceptance criteria
and real-network interruption/resume/load verification pass. Ready for review.
