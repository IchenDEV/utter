# Spec: Bound the shutdown drain so a stalled subsystem cannot strand the app

**Status:** approved
**Approved-by:** User, explicit approval in this conversation: 批准
**Approved-date:** 2026-10-26
**Upstream:** [intent.md](intent.md) (approved 2026-10-26)

## Context

Termination today:

- `AppDelegate.applicationShouldTerminate` (`Sources/App/OpenTypeApp.swift`) sets
  `terminating`, cancels the startup task, returns `.terminateLater`, then in a `Task`
  awaits `startup?.value` and `application?.stop()`. Success replies `true`; a thrown
  error shows an alert and replies `false`. Nothing bounds either `await`.
- `BuiltinApplication.stop()` removes its settings observer and awaits
  `PluginRuntime.stop()`.
- `PluginRuntime.stop()` revokes every scope first (ingress closes, `onRevoke` hooks
  restore system state such as the remote's HID key mapping), then `disposeScopes()`
  awaits each scope's disposals in reverse activation order (76 scopes). An effect leaves
  `PluginScope.effects` only after it returns, so a scope with a stalled effect keeps
  `hasPendingDisposal == true`.
- `PluginRuntimeTests.testShutdownWaitsForNonCooperativeWorkAndRejectsIngress` pins the
  runtime's patience on purpose: a drain waits for work that ignores cancellation.
  The bound therefore belongs above the runtime, not inside it.
- Stores write on every mutation with `.atomic` (`HistoryStore`, `DictionaryStore`,
  `CompositionStore`); model promotion uses `replaceItemAt`. Nothing is deferred to
  shutdown, so ending the process mid-drain cannot half-write a file.

Evidence for the failure (stranded 0.0.58 process, 2026-10-26) is in the intent: the
main thread idles inside `_handleAEQuit` -> `_shouldTerminate`, so the `Task` above
never called `reply(toApplicationShouldTerminate:)`.

Decisions already made (intent, "Decisions recorded"): exit at the bound; 5 s, shared
with the Sparkle relaunch path; a throwing drain logs and exits; ship the bound and the
diagnostic first; recovery guidance in release notes and README.

## Design

### 1. `BoundedWait` (new, `Sources/UtterRuntime/BoundedWait.swift`, portable)

```swift
package enum BoundedWaitOutcome { case finished, failed(any Error), timedOut }

package enum BoundedWait {
    package static func run(
        limit: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        operation: @escaping @MainActor () async throws -> Void
    ) async -> BoundedWaitOutcome
}
```

- The caller suspends on one `CheckedContinuation` guarded by a lock-protected one-shot
  box. Two unstructured `Task`s race to resume it: the worker (runs `operation`) and the
  timer (`sleep(limit)`, then times out).
- The worker winning cancels the timer. The timer winning calls `cancel()` on the worker
  as a courtesy and **abandons** it.
- A task group is deliberately not used. A group's `withTaskGroup` does not return until
  every child ends, and a stalled `await` on a continuation nobody resumes ignores
  cancellation, so the group would hang exactly like today's code.
- The one-shot box makes a late worker completion after the timeout a no-op (no double
  resume).
- `sleep` is injectable so tests use a fake clock and never wait.

### 2. Diagnostics from `PluginRuntime` (`Sources/UtterRuntime/PluginRuntime.swift`)

```swift
package private(set) var disposingPluginID: String?
package var pendingDisposalPluginIDs: [String] {   // dispose order
    scopes.reversed().filter(\.hasPendingDisposal).map(\.pluginID)
}
```

`disposeScopes()` sets `disposingPluginID` before `await scope.dispose()` and clears it
after. No change to `stop()` semantics, ordering, or error behavior.

### 3. `ApplicationShutdown` (new, `Sources/UtterBuiltins/Native/ApplicationShutdown.swift`)

```swift
@MainActor
package enum ApplicationShutdown {
    package static let limit: Duration = .seconds(5)
    package static func run(
        startup: Task<Void, Never>?,
        application: @MainActor () -> BuiltinApplication?,
        limit: Duration = limit,
        sleep: ... = default,
        log: Log = Log(service: SystemDiagnostics())
    ) async
}
```

Flow: `BoundedWait.run(limit)` over `await startup?.value; try await application()?.stop()`
(the application is read **after** the startup await, because startup is what sets it).
Then, always returning normally:

| Outcome | Log (`Log.error`, persisted by os_log) |
|---|---|
| `.finished` | nothing |
| `.failed(error)` | `Shutdown failed: <PluginShutdownFailure ids with error types, or the error type>; pending: [ids]` |
| `.timedOut` | `Shutdown exceeded 5s; disposing: <id or none>; pending: [ids]`, or `Shutdown exceeded 5s before startup finished` when no application exists |

Log contents are plugin ids and error type names only. No transcript, path, or user text.

### 4. `AppDelegate` (`Sources/App/OpenTypeApp.swift`)

```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminating else { return .terminateLater }
    terminating = true
    startup?.cancel()
    Task { [self] in
        await ApplicationShutdown.run(startup: startup, application: { self.application })
        sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
}
```

The alert-and-cancel branch is removed; `terminating` never resets because termination
can no longer be cancelled. `showFailure` stays for the startup-failure alert.

### Non-goals

No change to `PluginRuntime.stop()` semantics, plugin disposal code, Sparkle, signing,
release workflows, or settings. No user-visible setting or string. No `L()` entries.
The approved `2026-10-17-auto-update/spec.md` is not edited; this spec supersedes its
"nothing is force-killed" line only for a drain that does not end.

## Safety and failure modes

| Case | Behavior |
|---|---|
| Normal quit | `.finished`; reply `true` as soon as `stop()` returns. The timer never gates it. |
| A disposal never returns | Exit after 5 s; error log names the stalled and pending plugin ids. |
| A disposal throws | Logged with ids; exit. Replaces alert-and-cancel, which also stranded a Sparkle relaunch. |
| Startup never finishes | The same bound applies to `startup?.value`; log says startup was unfinished. |
| Worker finishes after the timeout | No-op; the one-shot box ignores it. |
| Repeated `applicationShouldTerminate` | `terminating` guard returns `.terminateLater`; one drain only. |
| Revocation ordering | `stop()` revokes all scopes before any disposal, so the HID key mapping restore and ingress closure have run before a timeout can end the process. A test pins this. |
| In-flight work cut at 5 s | A cancelled model download leaves a partial file that the existing retry recovery handles; a recording temp file is orphaned in the temp directory; an unsettled session's history record is not written, as for any quit mid-session. Stores are atomic. |
| Main thread blocked synchronously | Cannot be bounded in-process. This change covers an async stall, which is what was observed. |
| Process fails to exit after `reply(true)` | Not expected; checked in the real-process run (below). Residual risk if MLX/Metal teardown at `exit()` misbehaves with a loaded model. |
| Update from an installed build that has the stall | Not fixable by an update because the old process runs the drain. Guidance only. |
| Privacy | Logs hold ids and error type names, no content. |

## Test strategy

Maps to the intent's acceptance criteria.

| Criterion | Check |
|---|---|
| Stalled disposal exits within the bound, via the code `AppDelegate` uses | `OpenTypeTests/ApplicationShutdownTests`: real `BuiltinApplication.start(additional:)` with a plugin whose disposal awaits a never-resumed continuation; `ApplicationShutdown.run` with `limit: .milliseconds(200)` returns, asserted with an expectation timeout. Resuming the continuation afterwards must not crash. |
| Log names the outstanding plugin ids | Same test, recording `DiagnosticsService`; asserts the stalled id and `disposing:` text. |
| Normal drain is not delayed | Healthy app returns `.finished`-equivalent with no error log; `BoundedWaitTests` use a `sleep` that never returns and assert the result still arrives. |
| Throwing drain decided and tested | A plugin whose disposal throws: returns, logs its id. |
| Revocation precedes timeout | The stalled plugin's `onRevoke` flag is set when `run` returns. |
| `BoundedWait` correctness | `UtterRuntimeTests/BoundedWaitTests`: finish, fail, timeout with fake sleep, timer cancelled on finish, late worker completion is inert. |
| Runtime diagnostics | `PluginRuntimeTests`: `disposingPluginID` and `pendingDisposalPluginIDs` during a stalled `stop()`; existing `stop()` tests unchanged. |
| Gates | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`. |

Manual, recorded in `verification.md`:

1. Real-process stall. A **local, uncommitted** patch adds a stalling plugin to
   `BuiltinPlugins.registrations`. Run that dev build as a real menu-bar process, send
   the quit AppleEvent (`NSRunningApplication.terminate`), and time the exit and the
   error log. No hook ships; the patch diff is pasted into the evidence.
2. Normal quit on the release-style build (`bash scripts/build-app.sh`), with the model
   loaded and after a dictation, exits in under 1 s with no error log.
3. Measure quit during an active recording and during a model download. If either
   exceeds 5 s, the bound is revisited before approval.
4. Sparkle staged install over the patched old build, if feasible; otherwise listed as
   residual risk, as the intent allows.

## Rollout and rollback

- Order: PR, CI (`SDLC Gate`, tests, release-style build), merge to `main`, next
  SemVer release through the existing signed workflow. Publishing remains the
  maintainer's protected action; this change does not authorize a release.
- Release notes and README (`## Troubleshooting`, `## 常见问题`) carry one added entry:
  if Utter will not reopen after an update, force-quit it once (Activity Monitor) and
  reopen. Auto-generated notes list PR titles only, so the recovery sentence is added to
  the release body by hand at publish time.
- Observation: after release, search the unified log (subsystem `com.opentype.voiceinput`)
  for `Shutdown exceeded`. The first hit names the stalled plugin and starts the
  separate root-cause intent.
- Stop conditions: any crash or non-zero exit on a normal quit, or a data-store problem
  report.
- Rollback: revert the PR. No migration, no stored-format change, no setting added.

## Design decisions for review

1. The bound lives in `UtterBuiltins` plus a portable `BoundedWait`, not in
   `PluginRuntime.stop()`, to keep the runtime's patient-drain contract and its test.
2. Logs use `Log.error` because `info` messages are not persisted and could not have
   been read in this incident.
3. The 5 s limit is a constant, not a setting.
4. Real-process evidence comes from a local, uncommitted stall patch, never a shipped hook.
5. The approved 2026-10-17 spec stays unedited; supersession is recorded here.
