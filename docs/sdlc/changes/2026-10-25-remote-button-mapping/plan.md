# Plan: Configurable remote button mapping in Settings → Remote

**Status:** approved
**Approved-by:** User, explicit chat decision: approve plan and start Batch 0 now (2026-10-25)
**Approved-date:** 2026-10-25
**Upstream:** [spec](spec.md) (approved 2026-10-25)

Each batch is one commit, small enough to review alone. Before every commit run `swift build`, the batch's focused `swift test --filter`, and `bash scripts/ci-basic-checks.sh`. Every new file stays under 300 lines. The implementer is one agent; the independent verifier in Batch 9 is a different person or agent named by the user. The reference app's source is not reopened at any batch.

The branch is stacked on PR #130 (`cursor/swallow-remote-dictation-key`). Batches 1 to 8 touch no hardware and need no human at the keyboard. Only Batches 0 and 9 do.

## Work items

### Batch 0: measurements (no production code; feeds Batches 1, 4 and 5)

**Outcome (2026-10-25, details in [verification.md](verification.md)):** key table, observer under silence, timing and the Input Monitoring gate are measured; the granted-permission path and crash heal are not. Per spec D3 the starting values change to a **400 ms** double-click window (measured down to down) and keep **500 ms** for long press.

The earlier hardware sessions failed when a script waited for presses on a timer. This one is **count-driven**: the user starts it, each key is announced by sound and name, and the script moves on after a counted press, not after a time. A scratch tool lives under `evidence/` and is not part of the product. It must restore the remote's mapping on exit, and a clear command is printed before it starts.

- [x] Key table: for every RC003 key except power, one counted press and one long press. Record the HID usage page and usage, and the CG keycode, flags or system-defined data it produces with no mapping. Fills `RemoteButton` and the native-emulation table. Power is never asked for.
- [x] Observer under silence (two keyboard-page keys; a volume key is untested): for two keys of different kinds, map each to nothing with `hidutil`, and confirm the non-seizing `IOHIDManager` still sees every press and release while the CG layer sees none. Include a consumer-page key if the volume keys are on page 12.
- [~] Permission behavior (spec D2), partly: open fails without permission and the state flips to denied without a prompt; the grant path was not completed by the user: run the observer from a minimal ad hoc signed `.app` launched with `open`, so it carries none of Cursor's or Terminal's permissions. Record `IOHIDCheckAccess`, the `IOHIDManagerOpen` result and whether events arrive, before and after Input Monitoring is granted. This decides how the "no entries until live" gate is checked in Batch 4.
- [~] Crash heal, from PR #130's evidence only (mapping is lost at remote reconnect); sleep and idle disconnect unmeasured: with two keys mapped, force-terminate the process and record how long the keys stay silent and what returns them (reconnect, sleep, the manual clear command).
- [x] Timing, partly: ten natural double clicks and the short-press holds were measured; the long presses were deliberate holds of about 2 s, so the 500 ms threshold rests on the slowest short press (0.36 s) only. Original wording: ten natural double clicks and ten long presses on one key; record the observed intervals to confirm or adjust the 300 ms and 500 ms starting values.
- **Gate:** if the observer does not see presses under a mapping for any key kind, or Input Monitoring cannot be checked reliably, stop and bring the evidence back for a spec revision. Results are copied into `evidence/` as `.txt` and summarized in `verification.md`.

### Batch 1: model and gesture recognizer (pure)

- [x] `RemoteButton` table from Batch 0, `ButtonTrigger`, `ButtonAction`, `KeyChord`, `RemoteButtonProfile` with a versioned codec (an unknown action decodes to `native`).
- [x] `ButtonGestureRecognizer` with an injected clock: double-click window, long-press threshold, rapid repeats, release order, a second press during the wait, the hold ceiling.
- [x] `ButtonMappingPlan`: which buttons are owned.
- Tests: the recognizer table, codec round trip and unknown action, plan derivation. Focused filter: `RemoteButton`.

### Batch 2: policy and controller generalization

- [x] `RemoteKeyMappingPolicy` from one constant entry to an owned entry set that always contains F5 → nothing. `containsOurs`, `snapshot`, `applying`, `restoring` per owned source, foreign entries and other devices untouched.
- [x] `RemoteKeyMappingController`: a desired set that changes at runtime. A profile edit starts a fresh attempt and does not count as a re-apply, so editing is never reported as a conflict.
- Tests: the existing PR #130 cases keep passing unchanged; new cases for set apply and restore, leftover entries from a crash treated as ours, foreign entry for an owned source restored, edit without conflict, F5 invariant. Focused filter: `RemoteKeyMapping`.
- Done 2026-10-25: ownership became source based (an entry is ours iff destination is 0 and the source is F5 or a known remote button), `applying` takes the previously owned entries so it only restores what we silenced, read-back requires no stale entry of ours (`isSynced`). The 36 PR #130 tests pass unchanged; 31 new tests.

### Batch 3: settings

- [x] `remoteButtonMappingEnabled` (default false) and `remoteButtonProfile` in `SettingsValues`, `SettingsStore` load and persist.
- Tests: defaults, round trip, a corrupt stored profile falls back to empty without crashing.
- Done 2026-10-25. Module placement: the settings UI (`UtterPresentation`) and the persistence (`UtterData`) only see `UtterContracts`, so `RemoteButton`, `ButtonAction`, `KeyChord`, `ButtonTrigger`, `SystemKey` and `RemoteButtonProfile` moved there. `NativeKeyEvent` and `RemoteButton.nativeEvent` (key emulation) stay in `UtterRemoteMic`, together with the recognizer, the plan and the mapping controller. No behavior change from Batch 1.

### Batch 4: press source and coordinator

- [ ] `RemoteHIDPressSource`: non-seizing `IOHIDManager` matched on vendor and product, emitting press and release edges; permission check and request as measured in Batch 0.
- [ ] `RemoteButtonMappingCoordinator` (pure state, fakes for source, service and executor): off, needs permission, waiting for the remote, waiting for presses, active, conflict. **No entry beyond F5 is written until the source is confirmed live; losing the source or the permission removes them at once.**
- Tests: off makes zero writes, opens nothing and requests nothing; permission denied writes nothing; revoke removes owned entries but not F5; reconnect re-applies; quit restores. Focused filter: `RemoteButtonMappingCoordinator`.

### Batch 5: action executor

- [ ] `ButtonActionExecutor`: key chords and system keys through `CGEvent` at `.cghidEventTap`, `showDesktop`, `appSwitcher`, `openApp` through `NSWorkspace`, `native` emulation from the Batch 0 table. Dropped with a log line while secure input is on. No shell, script or URL action.
- Tests: a fake poster counts exactly the expected events per action; secure input drops; an unknown bundle id fails quietly.

### Batch 6: plugin wiring and diagnostics

- [ ] `RemoteMicPlugins` drives the coordinator from `onReady`, `onRevoke`, `onDispose` and the two settings; diagnostics carry button, trigger and action identifiers only.
- Tests: plugin lifecycle with fakes, including revoke and dispose restoring.

### Batch 7: settings page and strings

- [ ] `RemoteButtonMappingView`: master switch, twelve-key grid with three pickers per key, shortcut recorder, restore defaults, status line, and the permission explanation shown before the request. Split into small files.
- [ ] Strings in `en.lproj` and `zh-Hans.lproj` with parity.
- [ ] Real-window visual QA at the default size: off, active, needs permission, conflict; light and dark; English and Chinese. Screenshots under `evidence/`.

### Batch 8: docs and runbook

- [ ] Runbook entry: what the feature does, the Input Monitoring prompt, the manual clear command, what a crash looks like. Update the permission and privacy docs that list what Utter requests.

### Batch 9: verification (independent verifier)

- [ ] On the release-style build (`bash scripts/build-app.sh`), because permission behavior depends on the signed app: each key and trigger delivers the mapped action exactly once and the native key never reaches the frontmost app; unmapped keys unchanged.
- [ ] Rapid presses, sleep and wake, remote off and on, reconnect, quit, forced termination then relaunch, feature off, remote removed: every key returns to native.
- [ ] Permission denied and then granted; revoked while running.
- [ ] Voice key still records through the BLE path and never opens macOS Dictation, with the feature on and off.
- [ ] Record everything in `verification.md` with the verifier's identity. If the user waives any item, record it as a waiver, not as verification.

## Verification plan

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] Release-style build and the Batch 9 matrix on that build.
- [ ] Real-window visual QA (Batch 7).

## Human gates

- This plan needs explicit approval before Batch 0 starts.
- Batch 0 needs the user at the remote for about ten minutes, and its gate result goes back to the user before Batch 1 if it fails.
- `verification` needs explicit approval, then PR approval, then release approval for this high-risk change. The release is not cut without the independent verifier's recorded result, and not while PR #130 is unmerged.
- The licensing owner decides whether the clean-room disclosure in the intent is sufficient before this ships.
- Any further permission beyond Input Monitoring is a new decision and returns to the user.
