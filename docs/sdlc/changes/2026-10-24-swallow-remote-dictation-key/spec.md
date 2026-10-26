# Spec: Stop the Xiaomi remote's voice key from triggering macOS Dictation

**Status:** approved
**Approved-by:** User, explicit chat decision: 都批准 (2026-10-25 00:18 UTC+8)
**Approved-date:** 2026-10-25
**Upstream:** [intent](intent.md) (approved 2026-10-24; its "Revision 2026-10-24" section was confirmed with this spec on 2026-10-25)

## Context

Utter handles the Xiaomi remote's voice key through the BLE ATVV service (`UtterRemoteMic`). The same key also sends a HID keyboard report for F5 (usage `0x3E`, keycode 96, Fn flag, auto-repeat about 6 Hz), which macOS treats as the Dictation key. Nothing in Utter looks at that HID path today.

### Evidence (2026-10-24, device `RC003`, VID `0x2717`, PID `0x32B8`)

| Experiment | Result |
|---|---|
| A/B in a probe `NSTextView` (F5 delivered vs dropped) | Delivered: stray "I" / "We" inserted by Dictation, not by `keyDown`/`insertText`. Dropped: no text. This is the causal proof. |
| Spike: read-only `IOHIDManager` plus an active session tap dropping keycode 96 while the remote's HID F5 is down or within 80 ms after | 42 of 42 remote F5 events dropped, 0 leaked, no stray text; arrow-up and Return from the same remote passed. |
| Ordering | HID report arrived before the matching CGEvent in every measured press/release (0.6 to 4 ms). One control run showed a ~1.25 s late HID release on a main-run-loop manager; cause not proven. A second spike was invalid (it never called `IOHIDManagerOpen`). |
| **Device-level remap, real key presses** (same run, same listen-only tap) | Without mapping, 2 voice-key presses produced 17 F5 `keyDown` and 2 `keyUp` (the tap works). With `UserKeyMapping` F5 -> 0 applied via `hidutil` on the remote only (no root, no prompt, read back correctly, built-in keyboard mapping `(null)`), 3 presses produced **0** F5 events while arrow-up (keycode 126) from the same remote still arrived (2 events), and the user saw no stray "I". The mapping was reverted afterwards and read back empty. A first attempt without a without-mapping control was inconclusive and is not counted. Not yet verified: long holds, many presses, reconnect and sleep/wake persistence, ATVV session and delivery with the mapping on. |
| Gating fact | On the reproducing machine the installed Utter has `remoteMicEnabled = 0` (hotkey type Fn), and the stray text still happens. The F5 leak comes from the paired remote, not from Utter's remote-mic feature. |
| Delivery link | **Falsified.** With the F5 remap in place the stray text is gone, yet dictation into Cursor still ends `uncertain`. The delivery failure is a separate problem (Electron AX write); see the separate change `2026-10-25-electron-delivery-uncertain`. |

An earlier intent bullet used `DictationIMNotificationStartedListening` as evidence; it registers even when F5 is dropped and proves nothing. The intent revision replaces it with the A/B result.

### Reference project (`IchenDEV/remote-mic-app`, "SayAll", GPL-3.0)

Read for approach only; **no code is copied** and this design is an independent implementation from our own measurements. An earlier draft of this spec said the project does not handle the voice key. That was wrong; it handles it, with a different mechanism than the tap.

| Topic | What the reference does | Consequence here |
|---|---|---|
| Voice key | `RemoteVoiceFunctionMapper` sets the HID service property `UserKeyMapping` on services matching VID `0x2717` / PID `0x32B8`, mapping usage page 7 / `0x3E` (F5) either to Fn/Globe (default) or to usage `0` (a "neutralize" mode that makes the key produce no event). It reads existing mappings first, preserves unrelated ones, rolls back on partial failure, and restores on exit. | The key never becomes a CGEvent, so there is no tap, no attribution, and no ordering race. This becomes the primary mechanism (D1). |
| Persistence | Its bug notes record that after sleep/wake the HID service was not yet published when the Bluetooth bridge became ready (`matched=0`), the mapping was not re-applied, and the voice key stopped working until a manual reconnect. | The remap must be re-applied on every service (re)appearance and verified by read-back, with bounded retry. |
| Other keys | Separate seize-or-tap-based suppression for other buttons; native keycodes once wrong since the first release (`50` vs measured `10`). | Not needed for F5. Never add a key or model without measuring on hardware (D3). |
| Permissions | Requires Accessibility before neutralizing (its own policy), gates other paths on Input Monitoring. | Whether the remap itself needs any permission for Utter is unverified (D4). |

## Design

### Decisions on the intent's open questions

| # | Question | Decision |
|---|---|---|
| D1 | Mechanism | **Primary: device-level key remap.** Set `UserKeyMapping` on the remote's HID event service so F5 maps to usage `0`. It is scoped by construction to the matched device and other keys are untouched. **Fallback, not implemented unless the remap fails verification:** the earlier read-only `IOHIDManager` plus active tap design (evidence above). Seizing the device is rejected: it would hide the D-pad, OK and volume keys. |
| D2 | Gating | **Revised after the gating fact above.** My earlier recommendation (apply only while `remoteMicEnabled` is true) would not fix the reported machine, so it is withdrawn. Apply the remap whenever Utter is running and a matching remote is connected (the intent's stated default), controlled by a new setting `remoteKeyRemapEnabled`, default on, shown as a row on the Remote settings page so the user can turn it off; restore on setting off or quit. The remap observes no keys and changes only one key on one device. **The user must confirm this.** |
| D3 | Other models and keys | Match only `(VID 0x2717, PID 0x32B8)` and map only usage `0x3E`. Other products and keys stay inert until measured on hardware. `ARN9` is not covered. |
| D4 | Permission | The remap uses HID event system client calls, not a tap. Whether they need Accessibility or Input Monitoring for a Developer ID build is **unverified**; the first plan item measures it on a build with those grants removed. If a grant is needed, it is never auto-requested; the Remote settings page shows the state and a button that requests it on user action. |
| D5 | Leftover mapping after a crash | Accepted: until the remote's HID service is recreated (reconnect, sleep/wake, reboot), a crash leaves F5 mapped to nothing. Utter's voice path is ATVV, so it is unaffected. On next launch a mapping equal to our exact entry is treated as ours (idempotent). A documented one-line `hidutil` command clears it by hand. |

### Components (all in `UtterRemoteMic`)

1. `RemoteKeyMappingPolicy` (pure): the vendor/product table, the F5 source usage, and the merge and restore rules. `applying(existing)` removes any entry with the F5 source and appends ours; `restoring(original, current)` removes ours and re-adds a snapshotted original F5 entry from another tool; unrelated entries are never reordered or dropped.
2. `RemoteKeyMappingController` (state machine, injectable service provider and clock, so it tests without hardware): `apply`, `verify`, `restore`, bounded retry.
3. `Native/RemoteHIDServiceProvider`: the thin native layer over `IOHIDEventSystemClientCreateSimpleClient`, `IOHIDEventSystemClientCopyServices`, and `IOHIDServiceClientCopyProperty`/`SetProperty` for the `UserKeyMapping` property, filtered by vendor/product. Whether these symbols build under Swift 6 and ship under Developer ID signing and notarization is checked in the first plan item.
4. Wiring: the controller follows the app lifecycle and the new `remoteKeyRemapEnabled` setting, independent of the remote-mic toggle; when the remote mic is on, the bridge's ready transitions also trigger a verify. `RemoteMicPlugins` publishes its state.
5. Diagnostics and UI: `RemoteKeyGuardState` (`off`, `noRemote`, `waitingForService`, `active`, `conflict`, `failed`) and a re-apply counter in `RemoteMicDiagnostics`; a `RemoteKeyGuardRow` in the Remote settings page; strings in both `en.lproj` and `zh-Hans.lproj`.

### Behavior

- **Apply** when the feature is enabled and a matching service exists: read current mappings, snapshot any pre-existing F5 entry, write the merged list, read back, and report `active` only if the read-back contains our entry.
- **Re-apply** on each HID service appearance, and on each Bluetooth ready transition when the remote mic is on. Service appearance uses an IOHID event-system matching notification, or a light poll while running if none is available without extra permission; the first plan item decides. If no matching service exists yet, retry with backoff (bounded, about 10 attempts over 30 s), then `noRemote`/`failed`; never loop forever. This is the reference project's documented sleep/wake failure.
- **Verify** after apply and at the start of each remote voice session. A missing or foreign F5 entry triggers one re-apply, then `conflict` if another tool overwrites it again; the two tools never fight in a loop.
- **Restore** on disable, quit, and remote disconnect cleanup: remove our entry and re-add the snapshotted original, leaving everything else as found.
- All operations are idempotent and never touch other usages or other devices.

## Safety and failure modes

| Failure | Behavior |
|---|---|
| Remote not connected or not matched | Nothing is written; state `noRemote`. |
| Set fails or read-back mismatches | Roll back to the snapshot; state `failed`; F5 behaves as today. |
| Service recreated (reconnect, sleep/wake) | Mapping is gone with the old service; re-apply with bounded retry; until then F5 behaves as today. |
| Another tool maps F5 | Preserve its other entries; one re-apply, then `conflict`; on restore its original F5 entry returns. |
| Utter crashes | Mapping may stay until service recreation (D5); voice via ATVV is unaffected; manual clear command documented. |
| Setting turned off or quit | Restore as above. |
| Wrong device | The match is by VID/PID on the service, so other keyboards are never affected, including a built-in keyboard (read back as `(null)` in the mechanics check). |
| Privacy | No key events are observed at all; diagnostics are a state value and a counter. |

## Test strategy

| Acceptance criterion | Check |
|---|---|
| Zero keycode-96 events reach a probe view; no stray text | Hardware A/B with a probe app: control (feature off) shows stray text in 5 presses; treatment (feature on) shows 0 F5 events in at least 50 presses including holds of 5 s or more and rapid taps. This is the first plan item and is the go/no-go for D1; if it fails, fall back to the tap design. |
| ATVV session unchanged | Existing `UtterRemoteMicTests`; hardware session logs match before and after. |
| Other keys and other keyboards unaffected | Policy unit tests (unrelated entries preserved, order stable); hardware: arrows, Return, volume still work; built-in keyboard mapping read back as `(null)`. |
| No stuck state | Controller unit tests with a fake provider and clock: partial failure rollback, retry bounds, conflict, idempotent apply and restore. Hardware: remote off/on, sleep/wake, toggle off, quit, each followed by a read-back. |
| Delivery unaffected by F5 | Moved out: the `accepted` check belongs to the separate delivery change. Here only: no stray Dictation text during a delivery attempt. |
| Diagnostics expose state only | Unit test on `RemoteMicDiagnostics`; manual UI check in en and zh-Hans, light and dark. |
| Repo checks | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`. |

High risk: an independent verifier, who is not the implementer, reruns the hardware A/B, the lifecycle read-backs (reconnect, sleep/wake, toggle, quit), and records the result in `verification.md`.

## Rollout and rollback

1. Ship in a normal release; the remap runs while `remoteKeyRemapEnabled` (default on) is true and a matching remote is connected.
2. Runtime kill switch: the same setting in the Remote settings page, or the hidden default `remoteKeyRemapEnabled = false` for users who cannot open the page; either stops applying and restores the mapping without a new build.
3. Stop conditions: any report that another key or device stopped working, a stuck mapping after quit, or a conflict report from another tool. Response: kill-switch guidance, then revert.
4. Full rollback: revert the commit; the next remote reconnect or reboot also clears any leftover mapping. Manual clear at any time: `hidutil property --matching '{"VendorID":10007,"ProductID":12984}' --set '{"UserKeyMapping":[]}'`.
5. The manual workaround that stays valid at all times: System Settings > Keyboard > Dictation off.

## Approval record

The user approved this spec on 2026-10-25 (chat: 都批准), covering D1 (device-level remap primary, tap fallback), D2 (apply whenever a matching remote is connected, new default-on setting), D3 (RC003 / F5 only), D4 (permission measured first, never auto-requested), D5 (leftover mapping after a crash accepted), and the intent revision.

## Approval requested (superseded by the record above)

Please decide D1 (device-level remap as primary, tap as fallback), D2 (apply whenever a matching remote is connected, controlled by a new default-on setting; this returns to your stated default after the gating fact), D3 (only `RC003`/F5 for now), D4 (permission measured first, never auto-requested), D5 (accept a leftover mapping after a crash), and confirm the intent revision. Then this spec can move to `approved`; the plan stage starts only after that.
