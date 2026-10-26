# Plan: Bound the shutdown drain so a stalled subsystem cannot strand the app

**Status:** approved
**Approved-by:** User, explicit approval in this conversation: 批准
**Approved-date:** 2026-10-26
**Upstream:** [spec.md](spec.md) (approved 2026-10-26)

## Approach

Five small batches, each ending in a green gate before the next starts. Each batch is one
local commit on the worktree branch. Nothing is pushed and no PR is opened until
`verification.md` is complete and the maintainer says so. Publishing a release stays the
maintainer's protected action.

Every new or edited file stays under 300 lines. Current sizes: `PluginRuntime.swift` 112,
`OpenTypeApp.swift` 61, `PluginRuntimeTests.swift` 124.

## Work items

### 1. `BoundedWait` (portable)

- Add `Sources/UtterRuntime/BoundedWait.swift`: `BoundedWaitOutcome`, `BoundedWait.run`,
  and a private lock-protected one-shot box around one `CheckedContinuation`.
- Worker task runs `operation`; timer task runs the injected `sleep(limit)`. Worker win
  cancels the timer. Timer win cancels the worker and abandons it.
- Add `Tests/UtterRuntimeTests/BoundedWaitTests.swift`:
  - finishes: `.finished`, with a `sleep` that never returns (result still arrives).
  - throws: `.failed` carries the error.
  - stalls: worker awaits a never-resumed continuation, fake `sleep` returns at once,
    result is `.timedOut`.
  - timer is cancelled when the worker wins.
  - worker completes after the timeout: no crash, no second resume.
- Gate: `swift test --filter BoundedWaitTests`.

### 2. `PluginRuntime` diagnostics

- In `PluginRuntime.swift` add `disposingPluginID` (`private(set)`) and
  `pendingDisposalPluginIDs`. `disposeScopes()` sets the id before `await scope.dispose()`
  and clears it after. No other behavior changes.
- Extend `PluginRuntimeTests`: during a stalled `stop()` (a plugin whose `onDispose`
  awaits a never-resumed continuation, driven with `Task` and explicit yields),
  `disposingPluginID` names it and `pendingDisposalPluginIDs` lists it and the scopes
  still ahead of it in dispose order; after the continuation is resumed both are empty.
- Existing `stop()` tests must pass unmodified, including
  `testShutdownWaitsForNonCooperativeWorkAndRejectsIngress`.
- Gate: `swift test --filter UtterRuntimeTests`.

### 3. `ApplicationShutdown`

- Add `Sources/UtterBuiltins/Native/ApplicationShutdown.swift` per spec section 3:
  `limit = .seconds(5)`, injectable `limit`, `sleep`, `log`; application read after the
  startup await; outcome mapped to `Log.error` text (ids and error type names only).
- Add `Tests/OpenTypeTests/ApplicationShutdownTests.swift`, using a real
  `BuiltinApplication.start(additional:)` and a recording `DiagnosticsService`:
  - stalled disposal: `run(limit: .milliseconds(200))` returns; log has `Shutdown
    exceeded` and `disposing: <id>`; the plugin's `onRevoke` flag is already set;
    resuming the continuation afterwards does not crash.
  - throwing disposal: returns; log names the plugin id.
  - healthy application: returns, no error log, not delayed by the timer.
  - no application and a stalled startup: log says startup was unfinished.
- Gate: `swift test --filter ApplicationShutdownTests`.

### 4. `AppDelegate`

- In `Sources/App/OpenTypeApp.swift` replace the termination `Task` with the spec's
  version: `ApplicationShutdown.run`, then `reply(true)` on every outcome. Remove the
  alert-and-cancel branch; keep `showFailure` for startup failures.
- Gate: `swift build`.

### 5. Recovery guidance

- `README.md` under `## Troubleshooting` and `README_zh.md` under `## 常见问题`: one
  entry each. If Utter will not reopen after an update, force-quit it once (Activity
  Monitor, or `pkill -x Utter`; confirm the process name before running it) and reopen.
- Draft the v0.0.60 release-body sentence in `verification.md` so it is ready to paste at
  publish time. Auto-generated notes list PR titles only.
- Gate: `bash scripts/ci-basic-checks.sh` (it checks the READMEs).

## Verification plan

Automated, after item 5:

1. `bash scripts/sdlc-checks.sh`
2. `bash scripts/ci-basic-checks.sh`
3. `swift test` (full suite; compare failures against `main` before blaming this change)

Manual, evidence recorded in `verification.md` (command, time, result, excerpt):

1. **Real-process stall.** Apply a local, **uncommitted** patch adding a plugin whose
   disposal never returns to `BuiltinPlugins.registrations`. Build and launch it as a
   real menu-bar process, send `NSRunningApplication.terminate`, record exit time (expect
   about 5 s) and the persisted `Shutdown exceeded` line from
   `/usr/bin/log show --predicate 'subsystem == "com.opentype.voiceinput"'`. Paste the
   patch into the evidence, then `git checkout` it away and confirm `git status` shows
   no stray source change.
2. **Control for item 1.** Same build without the patch exits in under 1 s with no error
   log, so item 1 is attributable to the patch.
3. **Release-style build** (`bash scripts/build-app.sh`): normal quit with a model loaded
   and after one dictation exits in under 1 s with no error log.
4. **Quit during a recording and during a model download.** Record the times. If either
   exceeds 5 s, stop and bring the bound back to the maintainer before verification is
   marked ready.
5. **Sparkle staged install over the patched old build.** Try if the local appcast setup
   allows; otherwise list it as residual risk, as the intent permits.

Before the first manual run, the installed `/Applications/Utter.app` (0.0.59, healthy)
is left alone; dev builds run from the build directory and are quit afterwards so no
stray process remains.

## Risks and stop conditions

| Risk | Handling |
|---|---|
| A timeout test is flaky under CI load | The fake `sleep` removes wall-clock waits; the one real-time assertion uses a generous expectation timeout. |
| `swift test` already has unrelated failures | Compare with a clean `main` run first and report the difference, not a bare red. |
| Exit after `reply(true)` hangs in MLX/Metal teardown | Caught by manual items 1 and 3. If seen, stop and return to the spec; do not add a second force-exit path unreviewed. |
| Quit during recording or download exceeds 5 s | Manual item 4 stop condition. |
| Real-process patch leaks into a commit | It is never staged; `git status` and `git diff --stat` are checked and pasted before each commit. |

## Out of scope for this plan

Identifying which subsystem stalls (separate intent, driven by the first
`Shutdown exceeded` log), any Sparkle, signing, or workflow change, publishing a release,
and filing the GitHub incident issue (offered to the maintainer at the end).
