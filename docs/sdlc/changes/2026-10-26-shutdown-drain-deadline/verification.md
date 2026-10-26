# Verification: Bound the shutdown drain so a stalled subsystem cannot strand the app

**Status:** approved
**Approved-by:** User, explicit approval in this conversation: 批准 (accepts the unmeasured items listed below)
**Approved-date:** 2026-10-26
**Upstream:** [plan.md](plan.md) (approved 2026-10-26)

Commits on branch `cursor/33affdbd` (local, not pushed), base `origin/main` fd87c34:

| Commit | Content |
|---|---|
| d48bf10 | SDLC bundle: intent, spec, plan |
| 1219407 | `BoundedWait` and `BoundedWaitTests` |
| d8fca98 | `PluginRuntime.disposingPluginID`, `pendingDisposalPluginIDs`, test |
| 0d8f8bf | `ApplicationShutdown` and `ApplicationShutdownTests` |
| 274addc | `AppDelegate` replies after the bounded drain |
| 94d3e81 | README troubleshooting entries (English and Chinese) |

## Evidence: automated

| Gate | Result |
|---|---|
| `swift test --filter BoundedWaitTests` | 5 tests, 0 failures |
| `swift test --filter UtterRuntimeTests` | 32 tests, 0 failures. Existing `stop()` tests pass unmodified. |
| `swift test --filter ApplicationShutdownTests` | 5 tests, 0 failures |
| `swift test` (full, 2026-10-26 18:34) | exit 0. XCTest: 579 tests, 24 skipped, 0 failures. The 24 skips are tests gated on an env var that points at a local model (for example `UTTER_ANE_TEST_MODEL`). `CoreData ... contactsd` lines in the log are environment noise from existing tests. |
| `bash scripts/sdlc-checks.sh` | passed |
| `bash scripts/ci-basic-checks.sh` | passed (run after the README edit; no source change since) |
| `swift build` | passed, no warning from the new files |
| `bash scripts/build-app.sh --app-only` (release, arm64) | passed, including "Release artifact verification passed". Ad-hoc signed because no usable signing identity exists on this machine; not a release artifact. |

New tests, mapped to the intent's acceptance criteria:

| Criterion | Test |
|---|---|
| Stalled disposal returns within the bound, via the code `AppDelegate` calls | `ApplicationShutdownTests.testStalledDisposalReturnsWithinTheBoundAndNamesThePlugin` (real `BuiltinApplication.start`, plugin whose disposal never returns, `limit` 200 ms) |
| Log names the stalled and pending plugins | same test: `Shutdown exceeded 0.2s; disposing: test.stalled; pending: [...]` |
| Revocation precedes the timeout | same test: the plugin's `onRevoke` flag is set when `run` returns |
| A late completion after the timeout is harmless | same test resumes the stalled disposal afterwards; `BoundedWaitTests.testStalledOperationTimesOutAndALateCompletionIsInert` |
| Normal drain is not delayed or logged | `testHealthyDrainIsNotGatedByTheTimerAndLogsNothing` (timer that never fires), `BoundedWaitTests.testFinishedOperationIsNotGatedByTheTimer` |
| Throwing drain is decided and tested | `testThrowingDisposalIsLoggedWithIdsAndReturns` |
| Startup that never finishes is bounded | `testStartupThatNeverFinishesIsBoundedToo` |
| Runtime diagnostics | `PluginRuntimeTests.testStalledDisposalIsNamedWhilePendingAndClearsOnceItEnds` |
| The bound is 5 s | `testTheBoundIsFiveSeconds` |

## Evidence: real process

Machine: the maintainer's, with the installed `/Applications/Utter.app` 0.0.59 (PID 19716)
running throughout and never touched. Dev builds were launched with `open -n` from
`dist/` (gitignored, removed afterwards) using a copy of `scripts/build-and-run.sh` with its
`pkill -x Utter` line deleted, because that line would have killed the installed app. The
quit was sent by pid with `NSRunningApplication.terminate()`, which delivers the same quit
AppleEvent Sparkle sends. Times are wall clock from the quit request to process exit.

**1. Stalled subsystem (local, uncommitted patch).** The patch added one plugin,
`verify.stall`, whose disposal never returns. It is reverted; `git status` is clean.

```diff
@@ Sources/UtterBuiltins/Native/BuiltinPlugins.swift
+        let verifyStall = PluginRegistration(descriptor: PluginDescriptor(id: "verify.stall")) { context, _ in
+            try context.scope.onRevoke { Log(service: diagnostics).error("verify.stall revoked") }
+            try context.scope.onDispose {
+                Log(service: diagnostics).error("verify.stall disposing, never returns")
+                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
+            }
+        }
-        return try BuiltinRegistrationPolicy.replacing(data + ... + presentation + additional,
+        return try BuiltinRegistrationPolicy.replacing(data + ... + presentation + additional + [verifyStall],
```

Result: process exited **5.30 s** after the quit request. Persisted unified log
(`/usr/bin/log show`, subsystem `com.opentype.voiceinput`, error level):

```
18:36:13.724 E Utter[21511] verify.stall revoked
18:36:13.724 E Utter[21511] verify.stall disposing, never returns
18:36:18.892 E Utter[21511] Shutdown exceeded 5s; disposing: verify.stall; pending: [verify.stall, presentation.menu, presentation.about, updates.sparkle, speech.whisper, ... audio.speech-evidence]
```

Revocation ran at the start of the quit, 5.17 s before the timeout. The same message with
the pending list is what a field report would contain. Before this change the identical
stall would have left the process alive indefinitely.

**2. Control, same dev build without the patch** (full desktop composition, 10 s after
launch): exited in **0.43 s**; no `Shutdown` line in the log.

**3. Release-style build, normal quit** (`dist/Utter.app` from `scripts/build-app.sh
--app-only`, 40 s after launch, resident memory 1231 MB so the preloaded speech and
formatting models are in memory): exited in **0.16 s**; no `Shutdown` line in the log.

## Not verified, and why

| Item | Status |
|---|---|
| Quit during an active recording | Not measured. A recording needs the microphone grant, and this ad-hoc build is a different code identity from the installed app, so macOS would prompt. |
| Quit during a model download | Not measured. No download could be started without changing the maintainer's real model storage. |
| Quit during an in-flight HTTP or XPC session | Not measured. The HTTP interface is off in the maintainer's preferences, and turning it on for a test means writing to the shared preferences domain the installed app reads. |
| Sparkle staged install over a stalled old build | Not tried; needs a signed local appcast and a second signed build. The intent allows listing it as residual risk. |

The first three do not change what ships: whatever those operations do, quit is now capped
at 5 s and the cause is logged. What they would settle is whether a user quitting in the
middle of one of them sometimes loses work to the cap. The spec's analysis (stores write
atomically, a cancelled download leaves a partial file that existing retry handles, a
recording temp file may be orphaned, an unsettled session is not recorded) still applies and
is not measured here. Accepting that gap is the maintainer's decision at approval.

## Residual risk

- The stalled subsystem is still unidentified. The first `Shutdown exceeded` report names it
  and starts the separate root-cause intent.
- A copy of the app that is already running and stuck cannot be fixed by an update, because
  the old process runs the drain. Updating from 0.0.58 or 0.0.59 can still need one
  force-quit; the README entry says so.
- A synchronous block of the main thread cannot be bounded in-process. This change covers the
  asynchronous stall that was observed.
- If exit after `reply(true)` ever hung inside Metal or MLX teardown, this change would not
  help. Real-process runs 1 to 3 exited cleanly with models loaded.

## Release hand-off (maintainer's protected action)

Suggested sentence for the release body, which must be added by hand because generated notes
list PR titles only. The version number assumes the next release is 0.0.60; the README
entries also say "0.0.60", so change both if the number differs.

> If Utter will not reopen after updating, it is the previous copy still running: force-quit
> it once (Activity Monitor, or `pkill -9 -x Utter`) and open Utter again. From this version
> on, a quit that does not finish within 5 seconds ends on its own and logs which part held
> it up.

Observation after release: search the unified log for `Shutdown exceeded`. Rollback: revert
the PR; no migration, stored-format change or setting is involved.
