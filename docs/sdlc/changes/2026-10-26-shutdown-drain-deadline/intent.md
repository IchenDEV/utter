# Intent: Bound the shutdown drain so a stalled subsystem cannot strand the app

**Status:** approved
**Approved-by:** User, explicit approval in this conversation: 批准
**Approved-date:** 2026-10-26
**Upstream:** — (corrective intent for the 2026-10-26 "v0.0.59 will not open" incident; no GitHub incident issue has been filed yet)
**Risk:** Medium, user-visible runtime behavior on the quit and update path

## Problem

After Utter 0.0.58 installed v0.0.59 through Sparkle, the app did not relaunch and
could not be opened again. The v0.0.59 artifact itself is sound. The running old
process never finished quitting, and everything downstream waited on it.

Observed on the maintainer's machine on 2026-10-26 (unified log, `sample`, `lsof`):

- `/Applications/Utter.app` is still 0.0.58. Its process (started 2026-10-25 23:46)
  is alive more than 30 minutes after the update began.
- 14:47:40 Check for Updates from the menu bar; 14:47:46 appcast signature verified;
  14:47:55 download finished and Sparkle's `Autoupdate` and `Updater` started.
- 14:47:58.621 `Updater` sent the quit AppleEvent. 14:47:58.643 AppKit logged
  `applicationShouldTerminate: NSTerminateLater`. By 14:47:58.70 the menu-bar status
  item had been torn down. The app logged nothing further.
- The sampled main thread sits in `-[NSApplication _handleAEQuit]` ->
  `_shouldTerminate`, an idle nested run loop. No Utter thread is blocked, so an
  `await` inside `application.stop()` never resumed and
  `reply(toApplicationShouldTerminate:)` was never called.
- `Autoupdate` is idle in its run loop. It cannot install until the old process exits.
- The user therefore sees an app with no menu-bar icon that never exits. Opening
  Utter again only re-activates that stranded process.

Checks on the v0.0.59 DMG: Developer ID signature valid and notarized (`spctl`
accepted, `codesign --verify --deep --strict` passed), checksum matches, it launches,
loads the local LLM, and exits within one second when sent the same quit event from a
fresh start. The failure needs runtime state the fresh run lacked.

`AppDelegate.applicationShouldTerminate` waits for `BuiltinApplication.stop()` with no
upper bound, and 76 plugin scopes dispose in reverse order. Any disposal that awaits an
external event can stall forever. Candidates, not evidence: `XiaomiRemoteMicBridge.close()`
(waits for a CoreBluetooth retirement callback), `LocalModelAccessGate.close()` (waits
for in-flight model use), `RemoteLLMClient.shutdown()`, `SessionDriver.close()`.
The stalled subsystem is not identified.

The 2026-10-17 auto-update spec covered a drain that fails ("staged update applies at
next quit; nothing is force-killed"). It did not cover a drain that never ends, and
`stop()` has no bound.

## Outcome

Quitting Utter always ends the process in bounded time, whether the quit comes from
the user, the system, or Sparkle's relaunch. A shutdown that stalls is recorded with
the name of the subsystem that did not finish, so the next incident is diagnosable.
An update never leaves a half-dismantled app running.

## Scope

- The termination path: `AppDelegate.applicationShouldTerminate` and the
  `BuiltinApplication.stop()` / `PluginRuntime.stop()` drain.
- A diagnostic naming the plugin disposals still outstanding when the bound expires.
- Regression coverage for a disposal that never returns.
- User-facing recovery guidance for installs already stranded (see Constraints).

Non-goals:

- Redesigning the Sparkle integration, signing, notarization, or release workflows.
- Withdrawing or re-cutting v0.0.59.
- Fixing a specific subsystem's shutdown before it is identified with evidence.

## Constraints

- Shutdown must keep revoking scopes first, so ingress closes and system state that
  Utter changed (such as the remote's HID key mapping) is restored before any
  deadline can end the process.
- Hitting the bound must not corrupt on-disk stores (history, dictionary, plugin
  composition, downloaded models).
- A normal quit must not get slower and must not wait on a timer.
- This supersedes "nothing is force-killed" from `2026-10-17-auto-update/spec.md` for
  the case where the drain does not terminate. That needs explicit design approval.
- A process already running cannot be repaired by an update, because the old process
  executes the drain. Users already stranded must force-quit once. This change can
  only document that.
- Swift 6 with `.swiftLanguageMode(.v5)`, functional style, files under 300 lines.
  User-visible strings go through `L("key")` with `en` and `zh-Hans` entries.
- Keep every stage pending until the user approves that stage.

## Acceptance criteria

- With a plugin whose disposal never returns, a quit request completes and the
  process exits within the configured bound. An automated test proves it through the
  same code path `AppDelegate` uses, with an injected clock and no real waiting.
- When the bound expires, `Log.error` names every plugin id whose disposal was still
  outstanding. A test asserts the ids.
- When every disposal completes, termination is approved as soon as the drain ends,
  with no timer-induced delay. The existing `stop()` tests still pass.
- Behavior when the drain throws is explicitly decided and tested. Today it shows an
  alert and cancels termination, which also strands a Sparkle relaunch.
- The bound is one named constant. It is justified against measured normal shutdown
  time (under 1 s on the fresh v0.0.59 run) and recorded in `verification.md`.
- A release-style build confirms quit with an injected stalled disposal exits within
  the bound on a real window. The Sparkle installer staged-run evidence is recorded
  or listed as residual risk.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and `swift test` pass.
- Rollback is a revert of this change; no data migration is involved.

## Evidence

- Unified log of the stranded process, 14:47:55 to 14:48:21 on 2026-10-26.
- `sample` of the stranded process: main thread in `_handleAEQuit` -> `_shouldTerminate`.
- `sample` of `Autoupdate` (pid 93468): idle run loop, waiting for the host to exit.
- Release asset `Utter-0.0.59.dmg`, sha256
  `a99e7df9c86d4a12c9642cedfbf89735b27ed582526c954100ea9f4b9b64d428`, verified locally.
- Shipped dispose order, printed from `BuiltinPlugins` through
  `PluginCatalog.orderedRegistrations` (76 plugins; the first logged side effect is an
  audio engine stop at +11 ms).

## Containment (done, 2026-10-26)

At the maintainer's request the stranded 0.0.58 process (pid 43143) was terminated with
SIGTERM; it exited within 1 s. Sparkle's `Autoupdate` then completed the install and
relaunched. `/Applications/Utter.app` is 0.0.59, passes `codesign --verify --deep --strict`
and `spctl` (Notarized Developer ID), and the new process runs without entering the
quit path. Nothing else on the machine was changed. The defect remains in the code, so
the next update from any build that has the stall can strand the app again.

## Decisions recorded from the maintainer (chat, 2026-10-26)

These answer the open questions and are inputs to the spec. The intent itself was
approved separately ("批准", 2026-10-26).

1. At the bound, exit the process (supersedes "no force-kill" for a drain that does not
   end).
2. The bound is 5 s, and the Sparkle relaunch path uses the same one.
3. A throwing drain is logged and then exits like a stalled one, instead of an alert
   that cancels termination.
4. Ship the bound and the naming diagnostic first. Root-cause the stalled subsystem from
   the logged ids in a separate intent.
5. Put the force-quit-once recovery guidance in both the v0.0.60 release notes and the
   README troubleshooting section.

## Open questions

None.
