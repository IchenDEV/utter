# Verification: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `git diff --check` | Pass | No whitespace errors in the recovery implementation or tests |
| `bash scripts/ci-basic-checks.sh` | Blocked in this checkout | Current Linux image has no `swift`; exact `4fc4ee4` macOS baseline passed, but this patch needs a rerun |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `bash -n scripts/ci-basic-checks.sh scripts/sdlc-checks.sh` | Pass | Shell harness syntax is valid |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native` (full suite) | Not rerun for this patch | Exact `4fc4ee4` baseline: 656 XCTest executed, 10 skipped, 0 failures; 1 swift-testing passed; the cancel-fix adds one XCTest |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native --filter "ModelDownload\|DownloadStallWatchdog"` | Not rerun for this patch | Exact `4fc4ee4` baseline: 28 executed, 0 failures; this patch adds `testDuplicateJoinedBeforeCancelDoesNotRestart` |

The focused tests retain the exact Whisper scope, sibling preservation,
flat-cache completion, duplicate retry deduplication, delete serialization, and
unchanged-progress coverage. This patch replaces the old quarantine-only
counterexample with `testCancelledWriterUsingOriginalPathMustDrainBeforeRetry`
and `testDeleteWaitsForCancelledOriginalPathWriter`: both keep the writer's
original live URL after cancellation. The cancel → relocation → retry → delete
counterexample also has the old continuation recreate and rename into its
captured original URL; the retry and delete are held behind the drain. The exact
`4fc4ee4` baseline had all 28 focused tests passing on macOS; the new regression
test requires a fresh macOS run and is not claimed as executed here.

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
  **partial /研发阻塞**: retaining the per-key slot prevents path sharing and
  is covered by `testCancelledWriterUsingOriginalPathMustDrainBeforeRetry`,
  `testDuplicateJoinedBeforeCancelDoesNotRestart`,
  `testTwoConcurrentRetriesAfterCancelStartOnlyOneWriter`, and
  `testDeleteWaitsForCancelledOriginalPathWriter`. Late UI writes are rejected
  by the token guard. A dependency call that never returns still prevents a
  replacement from starting, so the original "always retry" acceptance is not
  complete; independent per-generation staging/commit is the remaining P0.
- Stalled download detection — **pass; recovery remains研发阻塞**.
  `DownloadStallWatchdogTests` fires on inactivity and stays quiet while
  progress arrives; the progress-signal test rejects unchanged callbacks, and
  `isCurrent` prevents late state writes. The watchdog cannot make a permanently
  hung dependency return, so it does not establish complete Resume recovery.
- Delete removes partial markers — implemented in `deleteWhisper`,
  `deleteLLM`, and `deleteASR`; covered indirectly by the recovery path tests.
- `swift test` execution — the exact `4fc4ee4` baseline passed on macOS (focused
  28 executed, full 656 XCTest with 10 skipped plus 1 swift-testing test); this
  cancel-fix adds one focused XCTest and awaits a fresh macOS rerun.

## Residual risk

- 等待旧 I/O 退出解决写入安全，但永久不退出时的恢复能力仍未证明，不能据此宣称完整重试验收通过。
- 真实网络中断→Resume→下载完成→加载使用的端到端证据继续保留为未完成项与真机验收门禁；未在本次测试中执行。
- The 120 s stall threshold is a judgment call; a very slow link with no progress
  reports for over two minutes would be failed and marked resumable.
- A transfer that ignores cancellation may leave the Resume request waiting until
  the dependency call returns; it can no longer affect model state or share its
  live paths with a replacement.

## Decision

Blocked pending both a fresh macOS run for this cancel-fix and the independent
per-generation staging/commit P0 design. The `4fc4ee4` macOS results prove the
finite-drain safety fix, not the original always-retry acceptance or the real
interrupted-download/load flow. Human approval is not recorded.
