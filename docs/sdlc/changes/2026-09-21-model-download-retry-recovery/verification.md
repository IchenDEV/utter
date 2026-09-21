# Verification: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `git diff --check` | Pass | No whitespace errors in the recovery implementation or tests |
| `bash scripts/ci-basic-checks.sh` | Blocked | Stops at `swift: command not found` in this Linux agent image |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `bash -n scripts/ci-basic-checks.sh scripts/sdlc-checks.sh` | Pass | Shell harness syntax is valid |
| `swift test` (full suite) | Not run | Reserved for full test suite run / external CI |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native --filter "ModelDownload\|DownloadStallWatchdog"` | Pass | 25 executed, 0 failures across ModelDownloadFailureMessageTests (3), ModelDownloadRecoveryTests (10), and ModelDownloadTasksTests (12) on macOS |

The focused tests were expanded after the previous unverified WIP attempt. They
now cover exact Whisper variant relocation, sibling preservation, flat-cache
completion after a post-relocation rename, old/new file writers using separate
generations, generation-scoped cleanup, duplicate retry deduplication,
retired-I/O delete serialization, and unchanged progress callbacks. All 25 focused
tests pass on macOS.

## Acceptance criteria

- Retry purges `.incomplete` markers — pass. `ModelDownloadRecoveryTests`
  covers hidden `.cache` traversal, whisper-variant scoping (a sibling variant's
  partial is preserved), and coverage of the materialized repo plus the shared
  Hub cache.
- Cancel makes the model resumable without sharing paths with the old transfer —
  implemented and covered by `testAbandonedWriterDoesNotBlockRetry`,
  `testTwoConcurrentRetriesAfterCancelStartOnlyOneWriter`, and
  `testRelocationIsolatesOnlyTheRequestedWhisperGeneration`. The file-level
  cancel → retry → delete case is covered by
  `testDeleteWaitsForRetiredGenerationBeforeRemovingLivePath`. The old writer
  is kept tracked for deferred cleanup and late UI writes are rejected by the
  token guard.
- Stalled download resolves — pass. `DownloadStallWatchdogTests` (fires on
  inactivity, stays quiet while progress arrives), the progress-signal test that
  a repeated unchanged callback does not count as progress, plus the `isCurrent`
  guards ensuring a late run cannot overwrite the retry's state.
- Delete removes partial markers — implemented in `deleteWhisper`,
  `deleteLLM`, and `deleteASR`; covered indirectly by the recovery path tests.
- `swift test` execution — pass on macOS for the focused suite (25 executed,
  0 failures); full suite execution and end-to-end device download round trips
  remain reserved.

## Residual risk

- No end-to-end interrupted-network retry (fail mid-transfer → resume → load the
  model) was performed; verification is unit level plus code inspection. The
  required download-to-model-load round trip remains a macOS/device-side gate;
  a manual recipe is in `plan.md`.
- The 120 s stall threshold is a judgment call; a very slow link with no progress
  reports for over two minutes would be failed and marked resumable.
- A transfer that ignores cancellation may leave a background task running until
  the process exits; it can no longer affect model state.

## Decision

Ready for review. Human approval is recorded separately.
