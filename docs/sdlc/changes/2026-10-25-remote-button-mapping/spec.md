# Spec: Configurable remote button mapping in Settings → Remote

**Status:** approved
**Approved-by:** User, explicit chat decisions: mechanism M3 and approve spec (2026-10-25)
**Approved-date:** 2026-10-25
**Upstream:** [intent.md](intent.md) (approved 2026-10-25). Implementation derives only from that intent's behavior inventory and from behavior measured on the RC003; the reference app's source is not reopened.

## Context

What exists on this branch (stacked on PR #130):

- `RemoteKeyService` and `RemoteKeyMappingController` read, write, verify, re-apply after reconnect or wake, and restore the remote's device-level `UserKeyMapping`. `RemoteKeyMappingPolicy` owns exactly one entry, F5 → nothing, and never touches other entries or other devices. The lifecycle hooks live in `RemoteMicPlugins` (`onReady`, `onRevoke`, `onDispose`), driven by `remoteKeyRemapEnabled`.
- `HotkeyManager` owns a **listen-only** event tap at `.cgSessionEventTap`, created only when `AXIsProcessTrusted()`. No code path requests Input Monitoring (searched: no `CGRequestListenEventAccess`, `CGPreflightListenEventAccess`, `IOHIDRequestAccess`).
- `NativeDeliveryKeys` already synthesizes keyboard events with `CGEvent(...).post(tap: .cghidEventTap)`.

Measured on the RC003 (vendor `0x2717`, product `0x32B8`) during PR #130's hardware session on 2026-10-25, with a non-seizing `IOHIDManager` counter and a CG event tap (evidence under that change's `evidence/`):

- It reports ordinary keyboard-page usages: voice key F5 = 62, right 79, left 80, down 81, up 82.
- Raw `IOHIDManager` events arrive **below** a device `UserKeyMapping`. With F5 → nothing in place, the raw counter saw 3 F5 presses while the CG layer saw none. So a device mapping can silence a key for the system while Utter still sees the press.

Not measured, and each must be before the design below is final: the usages and CG keycodes of OK, back, home, menu, TV and the volume keys (power is deliberately not pressed: it can sleep or shut down the Mac); whether a non-seizing `IOHIDManager` open from Utter needs Input Monitoring (Apple documents that it does for keyboards); whether private destination usages are viable; how long mapped keys stay dead after a crash; usable double-click and long-press timings.

## Design

Three layers. Only the last depends on the mechanism.

**1. Model (pure, in `UtterRemoteMic`).**
- `RemoteButton`: the RC003 key table (usage page 7 usage) for the twelve keys, filled in from Batch 0. The voice key is not in it.
- `ButtonTrigger`: single, double, long.
- `ButtonAction` (core slice): `native` (the key's own behavior, the default), `key(KeyChord)` (a key with modifiers, from a preset list or recorded), `systemKey` (volume up, down, mute, play/pause, previous, next), `showDesktop`, `appSwitcher`, `openApp(bundleID)`. No shell, script or URL action.
- `RemoteButtonProfile`: per button, one action per trigger. Codable with a version field; an unknown action decodes to `native`, never crashes. Stored as JSON under one settings key beside `remoteButtonMappingEnabled` (default false).
- `ButtonGestureRecognizer`: pure state machine, clock injected. A button with no double-click binding fires single on press with no delay. With one, single waits the window. A long press fires once at the threshold while held and consumes the release. Repeats and a missed release are bounded by a hold ceiling. Starting values (to be validated): double-click window 300 ms, long press 500 ms, ceiling 10 s.
- `ButtonMappingPlan`: from a profile, which buttons are **owned**. A button is owned only if some trigger has a non-`native` action. Unowned buttons are never touched.

**2. Device layer (generalizes PR #130).** `RemoteKeyMappingPolicy` changes from one constant entry to an owned entry set: F5 → nothing always, plus one entry per owned button. `containsOurs` becomes "contains every entry we own". `snapshot`, `applying` and `restoring` keep their rules per source usage: a foreign entry for a source we own is replaced and put back on restore unless a newer one appeared; every other entry is untouched. `RemoteKeyMappingController` keeps its state machine and gains a desired set that can change at runtime. A profile edit starts a fresh attempt (write the difference, read back, bounded retries) and must not count as a re-apply, otherwise editing a mapping would be reported as a conflict; only an entry that disappears after we wrote it counts. Pure and unit-tested like today.

**3. Press source and executor (mechanism-specific).** `RemotePressSource` emits `(button, press | release, timestamp)`. `ButtonActionExecutor` performs the action: key chords and system keys through `CGEvent` at `.cghidEventTap`, apps through `NSWorkspace`. `native` for an owned button is emulated by posting that key's own keycode or system key, so an owned button's default single click still does what it did.

### Mechanism: the decision for the human

| | **M3: silence above, observe below** | **M1: private keys** | M2: seize (previous app) |
|---|---|---|---|
| Native key silenced by | device mapping `usage → nothing` (PR #130's proven path) | device mapping `usage → private usage` | seize of the HID device |
| Presses seen by | non-seizing `IOHIDManager` on the same vendor and product | an **active** event tap that recognizes and drops the private keys | the seizing manager |
| Device identity | exact | none: a key event carries no device, so another keyboard's F13–F20 would be swallowed and F21–F24 viability is unknown | exact |
| Press and release | exact | key-repeat must be filtered | exact |
| New permission | **Input Monitoring** (new for Utter) | none beyond Accessibility, which Utter has | Input Monitoring |
| Blast radius | one entry per owned key | one entry per owned key plus a global active tap | all of the device's interface |

**Recommendation: M3.** It keeps device identity exact, reuses the mapping lifecycle that PR #130 already runs, and has no collision with other keyboards. Its cost is Input Monitoring, which the intent says needs re-approval. **M1** is the fallback if you do not want a new permission, with the collision risk accepted and a measured private-usage set. **M2** is rejected unless both fail.

With M3 the permission is requested only when the user turns the feature on, after the page explains why. **No mapping entry is written until the press source is confirmed live** (`IOHIDCheckAccess` granted and the manager open and matched). If permission is missing or revoked while running, every owned entry except F5 → nothing is removed at once and the page says what is missing. The remote must never end up silenced and unobserved.

**Settings page.** A new `RemoteButtonMappingView` section in Settings → Remote: the master switch, a plain grid of the twelve keys with three action pickers each, a "record shortcut" field (a local key monitor inside the settings window), "restore defaults", and a status line (off, waiting for the remote, active, needs permission, conflict with another tool). No drawn remote in the first slice. Split into small files; strings in `en` and `zh-Hans`.

**Settings model and wiring.** `SettingsValues` gains `remoteButtonMappingEnabled` and `remoteButtonProfile`. The remote plugin observes them like `remoteKeyRemapEnabled` and drives the controller's desired set, the press source and the executor from `onReady`, `onRevoke` and `onDispose`.

## Safety and failure modes

- **Off means untouched.** With the master switch off no extra entry is written, no press source is opened, no permission is requested, and nothing is posted. A fake service in tests records every call and must see none.
- **Crash while keys are owned.** The owned entries stay on the HID service until the remote reconnects or the Mac sleeps. With this feature that can leave up to twelve keys silenced, not only the voice key as in PR #130, so it is worse than #130 and must be measured (Batch 0). Mitigations: the feature is off by default; a one-line manual clear (`hidutil … --set '{"UserKeyMapping":[]}'`, which also clears the F5 entry) is documented; on the next launch the controller treats leftover owned entries as its own and repairs them (the `snapshot` rule already does this for F5); graceful quit restores first.
- **Permission lost or denied.** As above: no entries, a status line, the remote and the voice key keep working.
- **Remote asleep, reconnected, removed.** Entries live on the service; a new service gets them re-applied with the same bounded retries as today, and a removed one needs nothing.
- **Another tool holds the device or an entry.** A foreign entry for a source we own is recorded and restored; a second writer after one re-apply puts the page in `conflict` rather than fighting. A seizing app that starves the observer shows as `waitingForPresses` after a quiet period.
- **Stuck or rapid presses.** Each press edge is processed once; a missing release is closed by the hold ceiling; a second press during the double-click wait is a double click, not two singles.
- **Self-triggering.** Injected events never reach the raw HID observer. Under M1 they must be tagged and ignored.
- **Secure input.** While secure input is on, shortcut and key actions are dropped with a log line and not retried, so nothing is typed into a password field.
- **Privacy.** Logs and diagnostics carry button, trigger and action identifiers only. No text, no window content, no usage counts.
- **Invariants.** F5 → nothing is always part of the desired set while remap is enabled, so the voice key never opens macOS Dictation, with the button mapping on or off.

## Test strategy

- **Unit, deterministic:** the gesture recognizer table (double-click window, long-press threshold, rapid repeats, release order, second press during the wait, ceiling); entry-set policy (apply, restore, idempotence, foreign entries kept, F5 invariant); profile codec (version, unknown action); plan derivation (owned set); executor with a fake poster counting events; secure-input drop.
- **Integration with fakes:** off state makes zero writes, opens no source and requests no permission; permission denied writes nothing; revoke removes owned entries but not F5; reconnect re-applies; conflict reporting; quit restores.
- **Visual QA:** the real settings window at the default size, light and dark, English and Chinese, for off, active, needs-permission and conflict.
- **Real remote, independent verifier:** the matrix in the intent plus crash-heal time and F5 behavior with mapping on. Not run by the implementer.
- **Gates:** `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`.

## Rollout and rollback

- Ships default off. Nothing changes on upgrade. There is no telemetry, so observation is user reports.
- Rollback is the master switch (restores at once), the manual clear command, then reverting the change. Stop condition: any report of silenced keys after quit or crash pulls the release.
- Order: PR #130 merges first; this branch is rebased on it.

## Batch 0: measurements before implementation

1. For each key except power: HID usage and the CG keycode, flags or system-defined data it produces, from one counted press each.
2. Whether a non-seizing `IOHIDManager` open and `IOHIDCheckAccess` behave as documented from an Utter build without Input Monitoring.
3. Under M1: whether device mapping to F13–F24 produces distinct keycodes the tap can see, and whether they pass to apps when unhandled.
4. Time for silenced keys to return after a forced termination, with and without reconnect.
5. Practical double-click and long-press timings on the RC003.

## Decisions requested at spec approval

- **D1** Mechanism: M3 (recommended) or M1.
- **D2** If M3, approval to add Input Monitoring, requested only on first enable.
- **D3** The starting timings above.
- **D4** A plain grid, not a drawn remote, for the first slice.

## Decisions recorded at approval (chat, 2026-10-25)

- **D1** Mechanism **M3**.
- **D2** Input Monitoring approved, requested only when the user first turns the feature on, after the page explains why.
- **D3** Starting timings accepted as starting values; Batch 0 may adjust them and the change is noted in the plan.
- **D4** A plain grid, not a drawn remote, for the first slice.

Intent open questions as this spec leaves them: (1) answered by D1; (2) remotes beyond the RC003 stay out of the first slice; (3) coexistence is handled by the observed symptoms in the failure-mode entry "Another tool holds the device or an entry", with no detection of the other app by bundle id in the first slice; (4) Batch 0. M1 measurements (Batch 0 item 3) are dropped because M1 was not chosen.

## Decision recorded after Batch 0 (chat, 2026-10-25)

Batch 0 showed that Input Monitoring is required for M3's observer (`IOHIDManagerOpen` fails with `kIOReturnNotPermitted` without it) and the user reported that granting it through the system dialog and System Settings was inconvenient. The user was asked whether to switch to M1 and **chose to keep M3**. D1 and D2 stand, now with the cost seen first hand. Evidence: [verification.md](verification.md).

## Erratum 1: firing rule, key repeat, permission flow

**Status:** approved
**Approved-by:** User, explicit chat decision: approve erratum 1 and start Batch 1 (2026-10-25)
**Approved-date:** 2026-10-25

Found while analyzing Batch 0, not by a test. It corrects the design section and does not change the approved mechanism.

**Firing rule (replaces "fires single on press with no delay if no double click is bound").** A trigger counts as bound only if its action is not `native`. With window W (double click, measured from the first press to the second press) and threshold T (long press):

| Bound | Single fires | Double fires | Long fires |
|---|---|---|---|
| neither double nor long | at press | n/a | n/a |
| long only | at release, if held less than T | n/a | at T while still held; the release is consumed |
| double only | when W after the first press passes with no second press | at the second press; its release is consumed | n/a |
| double and long | as double only, but only when the first press was released before T | as above | as long only, on the first press |

A press with no release for the hold ceiling ends the sequence. A third press after a double starts a new sequence (no triple click). Buttons are independent state machines. The recognizer's test table covers all four rows, including a press that crosses T and a second press arriving just inside and just outside W.

**Key repeat.** The remote sends one press and one release per physical press; the repeats an app sees while a key is held are generated by macOS from the key being down. A silenced key therefore **does not auto-repeat in the first slice**: holding an owned arrow no longer scrolls or moves. This is stated on the page next to the key list. Emulated repeat is a follow-up, not part of this change.

**Permission flow (from Batch 0).** (a) `IOHIDRequestAccess` is called before `IOHIDManagerOpen`: a first open silently turns the state from unknown into denied with no prompt. (b) When the state is already denied the prompt does not return, so the page offers a button that opens System Settings → Privacy & Security → Input Monitoring. (c) After a grant the open is retried on app activation and by a short poll while the page is visible; if it still fails with `kIOReturnNotPermitted`, the status line says to restart Utter. Whether a restart is needed was not measured (the user did not complete a grant) and is checked on the signed build in Batch 9. (d) The "no entry beyond F5 until the source is live" rule is unchanged: it is gated on a successful open.

## Erratum 2: decisions found while building the page (Batches 6 to 8)

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准, in reply to the summary that listed these four decisions (2026-10-26)
**Approved-date:** 2026-10-26

The reply was a bare 批准 to a message that listed these four items under "needs your decision". It is read as approval of these four only. It does not approve `verification.md`, the PR or a release, and it does not name the independent verifier.

1. **The button mapping depends on the voice-key remap.** It runs only while `remoteKeyRemapEnabled` and `remoteButtonMappingEnabled` are both on. The key mapping controller is the only writer of the device mapping and its off switch must stop every write, so the mapping cannot be independent of it. The page shows the mapping switch off and disabled, with a line saying why, while the voice-key remap is off; the stored choice is kept.
2. **Eleven keys, not twelve.** The power key is not offered because it was deliberately not measured (it can sleep or shut down the Mac). This deviates from the approved intent's acceptance line ("the twelve keys"); the intent is left as approved and the deviation is recorded here. Adding power later needs a measurement and its own change.
3. **`NSInputMonitoringUsageDescription` in `Resources/Info.plist`**, English only like the other usage descriptions, as the explanation text for the one permission D2 approved. Whether macOS shows it in the dialog is not measured.
4. **Chinese wording** of the key names and the page text, as in the strings files at commit `bc9d1eb`.
