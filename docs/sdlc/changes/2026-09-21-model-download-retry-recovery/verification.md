# Verification: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `git diff --check` | Pass | No whitespace errors in the recovery implementation or tests |
| Staging/API source audit | Pass (Linux) | Locked-source inspection confirms `WhisperKit.download(downloadBase:)` writes below the injected base; `HubApi(downloadBase:cache:)` and `HubCache(cacheDirectory:)` are used for ASR; MLX receives a per-run `Downloader` with the same injected paths |
| Generation race / commit tests | Added; macOS execution pending | `testCancelledGenerationCannotPublishAfterReplacement`, `testDeleteArbitratesAgainstLateCancelledWriter`, `testCommitMaterializesHubSymlinkBeforeStagingCleanup`, and `testFailedCommitKeepsThePreviouslyPublishedModel`; the LLM path also reloads from the published directory after promotion |
| `bash scripts/ci-basic-checks.sh` | Blocked in this checkout | Current Linux image has no `swift`; exact `4fc4ee4` macOS baseline passed, but this patch needs a rerun |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `bash -n scripts/ci-basic-checks.sh scripts/sdlc-checks.sh` | Pass | Shell harness syntax is valid |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native` (full suite) | Not runnable here; macOS handoff required | Exact `4fc4ee4` baseline: 656 XCTest executed, 10 skipped, 0 failures; 1 swift-testing passed. This patch adds generation/commit coverage |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native --filter "ModelDownload\|DownloadStallWatchdog\|Utility"` | Not runnable here; macOS handoff required | The focused set includes the cancellation race, three-path staging seams, symlink cleanup, and failed-commit preservation tests |

The focused tests retain the exact Whisper scope, sibling preservation,
flat-cache completion, duplicate retry deduplication, delete serialization, and
unchanged-progress coverage. This patch replaces the rejected quarantine-only
drain with `testCancelledGenerationCannotPublishAfterReplacement`: the old
writer retains its token-scoped staging root while a new generation publishes,
then its late commit is rejected. `UtilityTests` additionally verifies that a
Hub-style symlink is materialized as a regular readable file before its staging
cache is removed, and that a broken staged tree leaves the previous live model
unchanged. These new tests require the macOS handoff and are not claimed as
executed in this Linux environment.

The dependency path audit is reproducible from the pinned `Package.resolved`:

- `swift-huggingface` `b7219594`, `HubClient+Files.swift:520-522` computes the
  absolute `incompleteBlobPath` before network I/O and `:665-672` appends then
  moves/replaces it.
- `swift-transformers` `2fa33e1f`, `HubApi.swift:823-856` computes the
  absolute `incompleteDestination` before the async client download.

Those reads establish why a directory rename cannot be accepted as generation
isolation; the new file-level tests mirror the same original-URL behavior.

## Acceptance criteria

- Retry purges `.incomplete` markers — pass. `ModelDownloadRecoveryTests`
  covers hidden `.cache` traversal, whisper-variant scoping (a sibling variant's
  partial is preserved), and coverage of the materialized repo plus the shared
  Hub cache.
- Cancel makes the model resumable without sharing paths with the old transfer —
  **implementation complete; macOS execution pending**: the three download
  stacks receive token-scoped roots; `testCancelledGenerationCannotPublishAfterReplacement`
  covers old-writer-never-returns/new-generation-completes/old-late-arrival;
  `testDuplicateJoinedBeforeCancelDoesNotRestart` and
  `testTwoConcurrentRetriesAfterCancelStartOnlyOneWriter` cover request
  ownership; `testDeleteArbitratesAgainstLateCancelledWriter` covers Delete
  publication arbitration.
- Stalled download detection — **implementation complete; macOS execution pending**.
  `DownloadStallWatchdogTests` fires on inactivity and stays quiet while
  progress arrives; the progress-signal test rejects unchanged callbacks, and
  `isCurrent` prevents late state writes. A real network stall/resume remains a
  macOS integration gate.
- Delete removes partial markers — implemented in `deleteWhisper`,
  `deleteLLM`, and `deleteASR`; covered indirectly by the recovery path tests.
- `swift test` execution — the exact `4fc4ee4` baseline passed on macOS (focused
  28 executed, full 656 XCTest with 10 skipped plus 1 swift-testing test); this
  P0 patch awaits a fresh macOS rerun.

## Residual risk

- Linux cannot execute Swift/XCTest or exercise the real WhisperKit/Hub/MLX
  network paths; macOS must verify the integrated download/load behavior.
- 真实网络中断→Resume→下载完成→加载使用的端到端证据继续保留为未完成项与真机验收门禁；未在本次测试中执行。
- The 120 s stall threshold is a judgment call; a very slow link with no progress
  reports for over two minutes would be failed and marked resumable.
- A transfer that ignores cancellation remains in its generation root until it
  returns; it can no longer affect model state or share a live path with a
  replacement. A long-lived retired task can retain disk space temporarily.

## Decision

Implementation is delivered in the current P0 patch. Acceptance remains open
until the independent macOS run proves the focused tests and a real
interrupted-download → Resume → model-load flow. The `4fc4ee4` macOS results
are baseline evidence only; human approval is not recorded.
