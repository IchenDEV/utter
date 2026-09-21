# Verification: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." (localization parity, resources, lexicons) |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `swift test` (full suite) | Pass | 642 tests, 10 skipped, 0 failures |
| `swift build` | Pass | `Build complete! (83.00s)` with the Command Line Tools toolchain |
| `swift test --filter "ModelDownload\|DownloadStallWatchdog"` | Pass | 14 tests, 0 failures |

Note on the test command: this machine has no downloadable Metal toolchain, so
the Xcode build backend cannot compile `mlx-swift`'s Metal sources. The suite was
run with the Xcode toolchain and `--build-system native`, which produced the same
642-test result as the repository's CI `swift test` step. `swift build` with the
Command Line Tools toolchain also succeeds.

## Acceptance criteria

- Retry purges `.incomplete` markers — pass. `ModelDownloadRecoveryTests`
  covers hidden `.cache` traversal, whisper-repo scoping, and coverage of the
  materialized repo plus the shared Hub cache.
- Cancel makes the model resumable — pass.
  `testCancelLetsRetryStartEvenIfTransferIgnoresCancellation` (a second run
  starts after cancel) and `testCancelledRunNoLongerReportsCurrent`.
- Stalled download resolves — pass. `DownloadStallWatchdogTests` (fires on
  inactivity, stays quiet while progress arrives) plus the `isCurrent` guards
  ensuring a late run cannot overwrite the retry's state.
- Delete removes partial markers — implemented in `deleteWhisper`,
  `deleteLLM`, and `deleteASR`; covered indirectly by the recovery path tests.
- `swift test` passes — pass (642 tests, 0 failures).

## Residual risk

- No end-to-end interrupted-network retry was performed; verification is unit
  level plus code inspection. Owner: reviewer / release validation.
- The 120 s stall threshold is a judgment call; a very slow link with no progress
  reports for over two minutes would be failed and marked resumable.
- A transfer that ignores cancellation may leave a background task running until
  the process exits; it can no longer affect model state.

## Decision

Ready for review. Human approval is recorded separately.
