# Intent: Stop the Xiaomi remote's voice key from triggering macOS Dictation

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (after the open-question defaults 1, 2 and 4 were stated)
**Approved-date:** 2026-10-24
**Upstream:** [2026-10-07 Xiaomi remote connection](../2026-10-07-xiaomi-remote-connection/intent.md) (this change narrows its "no key remapping or HID capture" non-goal)

**Risk lane:** High — it makes Utter drop keyboard events at the system input boundary and may touch the Input Monitoring / Accessibility permission path. The full bundle, an independent verifier, and an explicit rollback are required.

## Problem

With a Xiaomi Bluetooth voice remote paired (observed unit: `小米蓝牙语音遥控器`, model `RC003`, vendor `0x2717`, product `0x32B8`), pressing its voice key does two things at once:

1. It opens a voice session through the BLE ATVV service, which Utter handles.
2. It also sends a standard HID keyboard report for **F5** (keyboard usage `0x3E`, keycode 96, with the Fn flag set) to macOS, which Utter ignores. While the key is held, macOS auto-repeats it at about 6 Hz.

macOS treats F5 with Fn as the system Dictation key (`AppleDictationAutoEnable = 1`, Dictation enabled). The frontmost text field starts Apple Dictation, which listens on the Mac microphone and inserts what it hears. Two user-visible failures follow:

- **Stray text.** The user sees "i" / "I" typed repeatedly into whatever field is focused while using the remote, so normal typing is unusable.
- **Utter cannot write into the dialog.** Recent dictations transcribed and polished correctly but delivery ended with `Delivery completed: uncertain, confirmation: none` after a 3 s observation timeout (and once `notDelivered`). A text field that macOS Dictation holds open changes its value and selection, which the delivery checks (`NativeDeliveryTarget.isCurrent` and the value confirmation) read as a changed target. This link is inferred, not yet reproduced; the verification stage must confirm it.

### Evidence (2026-10-24, installed Utter 0.0.57, Developer ID signed)

- Raw HID capture of the remote: voice key gives report id 1 `01 00 00 3e 00 00 00` on press, all zeros on release; a CGEvent tap saw keycode 96 `keyDown`/`keyUp` with `autorepeat=1` while held, `kbType=41`, flags `0x800100`.
- A probe `NSTextView` in a normal app window received `keyDown code=96 chars=U+F708 repeat=true` while held. The focused window ended with text `We`, newline, `I`, none of it from any `keyDown`/`insertText` call, so it was inserted by Dictation (`insertDictationResult`).
- Unified log: the probe process registered `DictationIMNotificationStartedListening` at 22:55:33.109, 6 ms after its first F5 `keyDown` (22:55:33.103). Utter logged no session in that window, so Utter did not write the stray text. (**Superseded:** the notification registers on the first key event even when F5 is dropped, so it is not evidence; see Revision 2026-10-24.)
- The same capture showed key-state oddities from the remote: duplicated `keyUp` events and `repeat=true` `keyDown`s with no preceding fresh `keyDown`.
- HID ordering in the capture: for every press/release the HID report arrived before the matching CGEvent, within the same millisecond.

## Outcome

With the Xiaomi remote's voice key in use, macOS and other apps no longer receive the key's F5 events, so Dictation does not start, no stray text appears, and Utter's own recording and delivery work as they do for the keyboard hotkey. Everything else behaves as before.

## Scope

Affected: users who pair the Xiaomi voice remote, whether or not the remote microphone feature is enabled.

In scope:

- Identify F5 key events that originate from the Xiaomi remote's HID interface.
- Drop those events (`keyDown`, `keyUp`, auto-repeat) before they reach any app.
- Diagnostics so the Remote settings page can say whether the key is being absorbed.

Non-goals:

- Remapping the remote's other keys (D-pad, OK, Back, Home, volume), or capturing or logging key content.
- Suppressing F5 from the built-in keyboard or any other keyboard.
- Using the remote's F5 as a Utter hotkey. The voice session still comes from ATVV.
- Changing the ATVV session, release, or fallback logic.
- Changing the macOS Dictation setting for the user. Turning Dictation off remains the manual workaround.
- Other vendors' remotes.

## Constraints

- Never drop an event unless it is confirmed to come from the remote; on any doubt, pass it through.
- Do not hold or delay events. The tap callback must stay non-blocking and cheap; the system disables slow taps.
- No new entitlement or Info.plist key. If detection needs the Input Monitoring permission, that is a new permission path and must be decided in the spec and disclosed in the permission copy (see open question 1).
- No key content or per-key history in logs or diagnostics; counts and timestamps only.
- Off when Accessibility is not granted or the tap cannot be created: behavior is today's behavior.
- Must not regress the existing listen-only hotkey tap (`flagsChanged` / `keyDown`) or the NSEvent fallback.
- Developer ID signing and permission stability are unchanged.

## Acceptance criteria

- With the remote paired and connected, pressing and holding the voice key in a probe text view yields **zero** `keyDown`/`keyUp` events for keycode 96 and no dictated text. (**Revised 2026-10-24:** the original wording also required that `DictationIMNotificationStartedListening` is not registered; that signal is invalid, see below.)
- Under the same conditions Utter still starts and stops a voice session from the voice key through ATVV, with unchanged session logs.
- An F5 event that does not come from the remote (built-in keyboard, a different external keyboard, a synthetic event) passes through untouched. Covered by unit tests with injectable device identity and timing.
- No other key from the remote (arrows, Return, Escape, volume) is dropped.
- If the remote is not connected, the feature is off, Accessibility is missing, or the tap is disabled, no event is dropped and no new error surfaces.
- The tap is re-enabled after `tapDisabledByTimeout` / `tapDisabledByUserInput`, and dropping stops cleanly when Utter quits or the remote disconnects (no stuck-suppressed state, including after a duplicated or missing `keyUp` from the remote).
- With the fix, a remote-voice-key dictation into a normal text field ends with a delivery result of `accepted`, not `uncertain`, on the machine that reproduced the failure. If it still ends `uncertain`, this intent is reopened with the new evidence rather than closed.
- Diagnostics expose only whether suppression is active and a count of dropped events; no key content.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and `swift test` pass.

## Open questions

1. **Detection mechanism and permission.** Candidate: an `IOHIDManager` matched on the remote's vendor/product (read-only, no seize) to learn when the remote's F5 is down, combined with an active session tap that drops keycode 96 in that window. This likely needs Input Monitoring in addition to Accessibility. Alternatives (keyboard-type heuristic `kbType == 41`, or dropping all F5 while the remote is connected) need no new permission but can hit other keyboards. Decide in the spec.
2. **Seize versus drop.** Seizing the remote's HID interface would also hide its D-pad and OK keys from the Mac. Default assumption: do not seize; drop F5 only.
3. **Other Xiaomi models.** The `ARN9` Remote 2 / 2 Pro may send a different key for its voice button. Match by observed usage or by a configurable set? This unit only proves `RC003`/F5.
4. **Gating on the remote-mic setting.** Should suppression follow the "use remote microphone" toggle, or apply whenever a matching remote is paired (the stray text happens regardless)? Default assumption: whenever a matching remote is connected.

## Approval record

The user approved the intent in chat on 2026-10-24 after the defaults for open questions 1, 2 and 4 were stated in the review message. Question 3 had no stated default; the spec must propose one and the user confirms it at spec review. The spec still has to confirm each default is technically sound, including the permission question.

## Revision 2026-10-24 (evidence correction, found during the spec stage)

- **What changed:** the claim that `DictationIMNotificationStartedListening` proves Dictation started is withdrawn. A control run showed the notification registers on the first key event to a text view even when the F5 is dropped. The causal evidence is the A/B probe instead: with F5 delivered the field receives stray "I"/"We" text inserted by Dictation; with the remote's F5 dropped by the spike (42 of 42 events, 0 leaks) no text appears. The first acceptance criterion is reworded accordingly. No scope, constraint, or other criterion changes.
- **Still inferred:** that Dictation holding a text field open causes the `uncertain` deliveries. The existing criterion that the delivery ends `accepted` remains the proof.
- **Open question 3 default proposed in the spec:** match only `RC003` (VID `0x2717`, PID `0x32B8`) and keycode 96.
- **Mechanism no longer assumed to be an event tap:** the reference project showed a device-level alternative, a per-device HID `UserKeyMapping` that maps the voice key's F5 to usage 0 before macOS creates any event. The spec recommends it as primary and keeps the tap as fallback. Where this intent's wording is tap-specific, it applies to whichever mechanism ships: "off when Accessibility is missing or the tap cannot be created" means "off when the mechanism cannot be applied or verified"; "the tap is re-enabled after being disabled" means "the mapping is re-applied after the remote reconnects or wakes, and restored on disable or quit". Scope, outcome, and every other criterion are unchanged.
- **Delivery criterion split out (user-confirmed outcome, scope change pending confirmation):** after the F5 remap removed the stray text, dictation into Cursor still ended `uncertain` (user report 2026-10-24 23:58; log `Delivery completed: uncertain, confirmation: none`). The inferred link between Dictation and the delivery failure is **falsified**. The delivery problem is tracked in [2026-10-25 Electron delivery uncertain](../2026-10-25-electron-delivery-uncertain/intent.md). This change keeps its F5 scope; its acceptance criterion "a remote-voice-key dictation ... ends `accepted`" is replaced by "the F5 remap is not the cause of any remaining `uncertain` delivery", which the new change's evidence already shows.
- **Re-approval:** confirmed by the user on 2026-10-25 (chat: 都批准), together with the spec. That confirmation covers the evidence correction, the mechanism wording, the open-question 3 default, and moving the delivery criterion to the separate change. Until then the stage status above covers the original approval only.
