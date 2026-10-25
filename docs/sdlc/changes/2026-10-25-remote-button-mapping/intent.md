# Intent: Configurable remote button mapping in Settings → Remote

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (after the clean-room, core-slice and stacked-order decisions were recorded)
**Approved-date:** 2026-10-25
**Upstream:** User request in chat, 2026-10-25 ("在页面上也加一下相关的功能，可以改一下遥控器的映射，把那个之前的一版功能给迁过来"). Builds on [2026-10-24 swallow remote dictation key](../2026-10-24-swallow-remote-dictation-key/intent.md) (PR #130, which owns the device-level HID mapping this change extends) and [2026-09-21 remote mic integration](../2026-09-21-remote-mic-integration/intent.md) (which records the GPL/MIT licensing gate this change inherits).

**Risk lane:** High — it intercepts a keyboard device's events, injects synthetic input, launches applications, and may need a permission Utter does not request today. Full bundle, independent verification on a real remote, and an explicit rollback are required.

## Problem

The remote's keys other than the voice key can only do what macOS does with them as keyboard keys. The previous app lists twelve for the Xiaomi Remote 2 Pro: power, four arrows, OK, back, home, menu, TV, volume up and volume down. Which of them the RC003 sends, and as which usages, is not yet measured here (open question 4). Utter offers no way to change that. The user previously used a separate app, `remote-mic-app` (SayAll), whose **Key Mapping** page lets every button run a chosen action, and wants that capability inside Utter so one app owns the remote.

The previous app's behavior, inventoried from its public repository at `a5b272acc1` (2026-08-30): its README, one screenshot of the page, and the source files `RemoteButtons.swift`, `RemoteButtonGestureRecognizer.swift` and `RemoteMappingCanvas.swift`. The agent that drafted this intent read that source to build the inventory. No code, screenshot or string was copied into this repository, but the reading is disclosed here because it limits what "clean-room" can mean for that agent; the licensing owner decides whether it matters (see Decisions recorded below).

- A page showing the remote with each key's actions; a master switch for custom mapping; "restore defaults"; "lock the key being edited while it is pressed".
- Per key, three triggers: single click, double click, long press.
- Actions grouped as basic keys (Escape, Return, Cmd-Return, copy/paste/undo/find/save/close, arrows, scroll, delete), system and media (show desktop, app switcher, context menu, volume, mute, play/pause, previous/next), custom (any recorded keyboard shortcut, focus the front app's input field, open a chosen app, toggle long recording) and a preset list of common applications.
- The key's native event is suppressed so only the mapped action happens. This needs Input Monitoring to see the keys and Accessibility to send the action.
- The voice key is fixed and cannot be remapped.

Two facts constrain a port:

1. `remote-mic-app` is **GPL-3.0** and is a fork of `HD838A/remote-mic-app`, whose main author is not the owner of this repository; Utter is **MIT**. The 2026-09-21 bundle already records that no code from it may be treated as acceptable without an explicit decision by a human licensing owner.
2. Utter requests Accessibility today and does **not** request Input Monitoring. The previous app's mechanism would add a new permission category.

## Outcome

- Settings → Remote shows the remote's keys; the user can give each non-voice key a single-click action and, optionally, double-click and long-press actions, chosen from a defined set.
- Nothing changes until the user turns the feature on. With it off, every key behaves exactly as it does today, and Utter does not touch the device any more than it already does.
- The voice key stays reserved for Utter's dictation, and PR #130's guarantee that it never opens macOS Dictation is unchanged.
- Quitting, crashing, or turning the feature off returns every key to its native behavior.

## Scope

- A pure model of keys, triggers and actions, and a gesture recognizer (single, double, long), unit-tested.
- A mechanism that detects the remote's key presses and, for mapped keys only, suppresses the native event and performs the action. The mechanism is chosen in the spec.
- A Settings page, a master switch, restore defaults, persistence, en and zh-Hans strings.
- A recommended first slice: the twelve non-voice keys; actions limited to keyboard keys and shortcuts, system volume and media, show desktop and app switcher, a user-recorded shortcut, and opening an installed app; the Xiaomi RC003 only (vendor `0x2717`, product `0x32B8`).
- Non-goals unless the user widens them: focus-input and accessibility-recorded targets, toggling long recording, macros, a statistics page, several remotes at once, iPhone, Watch and web remote paths, voice-key trigger modes (Fn or Command emulation), importing settings from `remote-mic-app`, any shell or script action.

## Constraints

- **Licensing.** No code, assets, screenshots or strings from `remote-mic-app` enter this repository unless the human licensing owner records an explicit decision. The default plan is a clean-room implementation from the observable behavior listed above. Whoever writes the code must not copy from the reference while doing so, and the licensing owner should say whether an implementer who has read the reference source (including the drafting agent) is acceptable or whether a fresh implementer is required.
- **Permissions.** Reuse the existing Accessibility flow. If the chosen mechanism needs Input Monitoring or any permission Utter does not request today, the spec must say so, the page must explain it before asking, and this intent must be re-approved. No permission is requested until the user turns the feature on.
- **Reversibility.** A graceful quit restores native key behavior at once. A crash leaves at most what PR #130 already documents, with a one-line manual recovery, and a relaunch repairs it. Never leave a key dead.
- **Coexistence.** The mapping must not weaken PR #130's F5 swallow and must not break the BLE voice path. If `remote-mic-app` is running and holds the device, Utter must detect it and say so instead of fighting for the device.
- **Safety of actions.** Opening an app uses a bundle identifier from the installed-app list or a user-chosen app bundle; there is no shell or script action. Shortcut actions are synthesized only while the feature is on and a key is mapped.
- **Privacy.** Logs and diagnostics hold key names, trigger names and action identifiers only; never typed text, never window or document content, no usage statistics.
- Default off, and a silent upgrade changes nothing. Strings go through `L()` with `en` and `zh-Hans` parity. Files stay under 300 lines.

## Acceptance criteria

- The key, trigger and action model and the gesture recognizer are covered by deterministic tests: a double-click window, a long-press threshold, rapid repeats, release order, and a key that is pressed again during the double-click wait.
- With the feature off, a fake device service records no seize, suppression or injection calls (test), and on a real remote every key behaves as before.
- With the feature on and a key mapped, one press delivers the mapped action exactly once and the native key never reaches the frontmost app (observed at the event layer on the real remote). An unmapped key keeps its native behavior.
- Quit, forced termination followed by relaunch, turning the feature off, and removing the remote each return every key to native behavior. The recovery path is exercised on the real remote.
- The voice key still records through the BLE path and still never opens macOS Dictation, with the feature on and off.
- The Settings page lists the twelve keys with their three triggers, saves choices across relaunch, restores defaults, and in a real window at the default size renders without clipping in light and dark appearance, English and Chinese.
- If a required permission is denied, the page says what is missing and why, mapping stays inactive, and the remote and the voice key keep working.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh` and `swift test` pass. A verifier other than the implementer runs the real-remote matrix: pair, each key and trigger, rapid presses, sleep and wake, reconnect, quit and crash recovery, and permission denied.

## Decisions recorded from the user (chat, 2026-10-25)

These answer open questions and are not an approval of this intent.

- **Licensing:** clean-room reimplementation from the observable behavior in this intent. No code, assets, screenshots or strings are taken from `remote-mic-app`. The drafting agent read the reference source to build the inventory above, so from here the spec and the implementation derive only from this inventory and from behavior measured on the RC003, and do not reopen the reference source. Whether that disclosure is enough, or a fresh implementer is needed, stays with the licensing owner.
- **First slice:** the core slice named in Scope (twelve keys, three triggers; keyboard, system and media, recorded shortcut, open an installed app; RC003 only).
- **Order relative to PR #130:** PR #130 stays open and unmerged for now. This branch is stacked on it and will be rebased when it merges.

## Open questions

1. **Mechanism.** The previous app seizes the HID device and injects its own events. An alternative reuses PR #130's device-level key mapping to move each button to a private key and recognizes it in Utter's existing event tap, which avoids a seize and may avoid Input Monitoring. Decide in the spec after measuring both on the RC003. Any new permission category sends this intent back for re-approval.
2. **Which remotes beyond the RC003.** The previous app's screenshot shows the Xiaomi Remote 2 Pro, which may use a different product id. Out of the first slice.
3. **Coexistence with `remote-mic-app`** when both are installed: detect and warn (recommended), or take over.
4. **Which of the twelve keys the RC003 actually sends, and as which usages.** To be measured before the spec fixes the key table.
