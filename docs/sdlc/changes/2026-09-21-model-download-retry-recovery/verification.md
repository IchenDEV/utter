# Verification: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `git diff --check` | Pass | No whitespace errors in the recovery implementation or tests |
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." on macOS |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `bash -n scripts/ci-basic-checks.sh scripts/sdlc-checks.sh` | Pass | Shell harness syntax is valid |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native` (full suite) | Pass | 656 XCTest executed, 10 skipped, 0 failures; 1 swift-testing passed (total 657 executed, 10 skipped, 0 failures) on macOS |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native --filter "ModelDownload\|DownloadStallWatchdog"` | Pass | 28 executed, 0 failures across DownloadStallWatchdogTests (3), ModelDownloadFailureMessageTests (3), ModelDownloadRecoveryTests (10), and ModelDownloadTasksTests (12) on macOS |

The focused tests retain the exact Whisper scope, sibling preservation,
flat-cache completion, duplicate retry deduplication, delete serialization, and
unchanged-progress coverage. This patch replaces the old quarantine-only
counterexample with `testCancelledWriterUsingOriginalPathMustDrainBeforeRetry`
and `testDeleteWaitsForCancelledOriginalPathWriter`: both keep the writer's
original live URL after cancellation. The cancel → relocation → retry → delete
counterexample also has the old continuation recreate and rename into its
captured original URL; the retry and delete are held behind the drain. All 28
focused tests pass on macOS.

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
  implemented by retaining the per-key slot until dependency I/O returns and
  covered by `testCancelledWriterUsingOriginalPathMustDrainBeforeRetry`,
  `testTwoConcurrentRetriesAfterCancelStartOnlyOneWriter`, and
  `testDeleteWaitsForCancelledOriginalPathWriter`. Late UI writes are rejected
  by the token guard even while the cancelled task drains. 等待旧 I/O 退出解决
  了写入安全，但永久不退出时的恢复能力仍未证明，不能据此宣称完整重试验收通过。
- Stalled download resolves — pass. `DownloadStallWatchdogTests` (fires on
  inactivity, stays quiet while progress arrives), the progress-signal test that
  a repeated unchanged callback does not count as progress, plus the `isCurrent`
  guards ensuring a late run cannot overwrite the retry's state.
- Delete removes partial markers — implemented in `deleteWhisper`,
  `deleteLLM`, and `deleteASR`; covered indirectly by the recovery path tests.
- `swift test` execution — pass on macOS for both the focused suite (28 executed,
  0 failures) and the full suite (656 executed, 10 skipped, 0 failures + 1 swift-testing
  test passed).

## Residual risk

- 等待旧 I/O 退出解决写入安全，但永久不退出时的恢复能力仍未证明，不能据此宣称完整重试验收通过。
- 真实网络中断→Resume→下载完成→加载使用的端到端证据继续保留为未完成项与真机验收门禁；未在本次测试中执行。
- The 120 s stall threshold is a judgment call; a very slow link with no progress
  reports for over two minutes would be failed and marked resumable.
- A transfer that ignores cancellation may leave the Resume request waiting until
  the dependency call returns; it can no longer affect model state or share its
  live paths with a replacement.

## Decision

Ready for review. Human approval is recorded separately.
