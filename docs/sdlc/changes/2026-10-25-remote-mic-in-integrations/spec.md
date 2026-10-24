# Spec: Move the Xiaomi remote microphone controls into Integrations

**Status:** pending approval            # draft | pending approval | approved | rejected | blocked
**Approved-by:** —
**Approved-date:** —
**Upstream:** intent.md (approved 2026-10-25)
**Risk:** Medium. User-visible Settings placement and one help string. No permission, data format, signing or release change.

## Context

- The three remote-microphone rows live in `GeneralSettingsView.swift` as the
  private `remoteMicControls` block, called right after `microphonePicker` in the
  Audio section: a toggle bound to `settings.remoteMicEnabled`, disabled when
  `platform.hasRemoteProvider` is false; when on, a connection line
  (`platform.remoteState.summary`) and a gain slider bound to
  `settings.remoteMicGainDB` (0 to 24, step 1) with an `N dB` label.
- The file has 279 lines. The block and its call are about 25 lines.
- Capture does not depend on these rows. `RemoteMicPlugins.capture` and the
  remote session binding read `remoteMicEnabled` and `remoteMicGainDB` from the
  settings service. The rows are only a view over those two keys.
- The Integrations tab is one grouped `Form` built by `SettingsGroupPage` from
  member pages sorted by `(order, id)`. Members today: `presentation.integrations`
  (order 0: Developer interface, Registered apps, HTTP) and
  `presentation.configuration` (order 10: Plugins). Each member returns bare
  `Section`s. `AppSettings` reaches them through the window's environment.
- `PlatformProjection` carries `remoteState` and `hasRemoteProvider`. It is built
  per plugin by `PresentationPlugins.platform(_:)` from
  `platformRequirements` (remote control, login item, audio devices and screen
  optional; diagnostics required). General, About and onboarding do this today.
- `BuiltinCompositions.bundles` builds the `desktop` bundle from every
  registration, so a new built-in plugin is on by default, with no
  `plugins.json` change. `recoveryIDs` is an allow list that does not include
  the Integrations page, so recovery mounts only Plugins.
- Only one string points at the old place: `settings.remote_mic_help` says the
  keyboard shortcuts use the Mac microphone "selected above" (`上方选择的`). A
  search of strings, `Info.plist`, README and docs found no other text, and no
  deep link, that sends the user to General for the remote microphone.

## Design

### D1. A plugin of its own, in the Integrations group (answers intent questions 1 and 4)

New plugin `presentation.remote-mic`, registered in
`PresentationPlugins+Settings.swift` and listed in `BuiltinPlugins` next to
`integrations()`:

```swift
package static func remoteMic() -> PluginRegistration {
    contribution(id: "presentation.remote-mic", role: .settings, order: 5,
        label: "settings.remote_mic", symbol: "dot.radiowaves.left.and.right",
        group: SettingsGroup.integrations.id, requires: platformRequirements) { context, _ in
            let platform = try platform(context)
            return { _ in AnyView(RemoteMicSettingsView(platform: platform)) }
        }
}
```

- Order 5 sorts it after `presentation.integrations` (0) and before
  `presentation.configuration` (10). The page reads: Developer interface,
  Registered apps, HTTP, Xiaomi remote wireless mic, Plugins. Plugins stays last.
- The id is `presentation.remote-mic`, not `presentation.remote`.
  `presentation.remote` was the id of the Remote tab that this branch removed. The
  recovery tests use it as an id this build does not know, and it must stay
  unknown.
- It is not added to `recoveryIDs`.
- The tab, its label, symbol and order (40) are unchanged. `SettingsGroup` and
  `SettingsTabLayout` need no change.

Why not inside `IntegrationsSettingsView`:

| | Own plugin (recommended) | Inside `IntegrationsSettingsView` |
|---|---|---|
| Disable one without the other | Yes, one `plugins.json` row | No |
| What it requires | `platformRequirements` on its own plugin | Adds `platformRequirements` to `presentation.integrations`, so a missing diagnostics service would also remove Developer interface, Registered apps and HTTP |
| Placement test | Tab members, `[integrations, remote-mic, configuration]` | Needs view rendering |
| Cost | One registration and one 45-line view | A second environment object on a view about client registration |

### D2. `RemoteMicSettingsView`

New file `Sources/UtterPresentation/UI/RemoteMicSettingsView.swift`, about 45
lines:

- `@EnvironmentObject private var settings: AppSettings` and
  `@ObservedObject var platform: PlatformProjection`. The projection is passed
  in, not placed in the environment, so no wrapper sits between the group `Form`
  and its `Section`.
- Body: `Section(L("settings.remote_mic")) { ... }`. The rows are the current
  block, unchanged: same toggle label and help text, same `.disabled`
  condition, same status row, same slider range, step and `N dB` label. The
  header matches how the other Integrations sections are titled, with a plain
  string `Section`. Its text repeats the toggle label, as Developer interface
  already does.
- No new state and no new settings. The view reads and writes
  `remoteMicEnabled` and `remoteMicGainDB` through `AppSettings`, the same
  bindings as today.

### D3. General

`GeneralSettingsView.swift` loses `remoteMicControls` and its call. The Audio
section keeps its other rows in their order. `platform` stays, because the
microphone picker and launch-at-login use it. The file drops to about 254
lines.

### D4. Help text (answers intent question 3)

`settings.remote_mic_help` changes in place. No key is added or removed, so
`en` and `zh-Hans` key parity is unaffected.

| | Before | After |
|---|---|---|
| en | Hold the Xiaomi Bluetooth Remote 2 Pro voice key to record from it. Keyboard shortcuts keep using the Mac microphone selected above. | Hold the Xiaomi Bluetooth Remote 2 Pro voice key to record from it. Keyboard shortcuts keep using the Mac microphone chosen in General. |
| zh-Hans | 按住小米蓝牙遥控器 2 Pro 的语音键时使用遥控器麦克风；键盘快捷键仍使用上方选择的 Mac 麦克风。 | 按住小米蓝牙遥控器 2 Pro 的语音键时使用遥控器麦克风；键盘快捷键仍使用在“通用”页选择的 Mac 麦克风。 |

"General" and "通用" are the current values of `tab.general`. A unit test ties the
help text to `tab.general` in each language, so a tab rename cannot leave the
pointer stale.

### D5. Move, not copy (intent question 2)

The controls leave General completely. Two copies would bind to the same two
keys and add a second place to keep in step for no gain.

### D6. Branch and landing (intent question 5)

The change goes on `cursor/settings-tab-consolidation` as separate commits: one
per SDLC document stage, and one code commit. Reverting that code commit
restores the controls to General. Whether the branch is pushed, and in what
order it lands against `main`, stays the owner's separate decision.

### Files

New: `UI/RemoteMicSettingsView.swift`, `Tests/OpenTypeTests/SettingsRemoteMicPlacementTests.swift`.
Edited: `GeneralSettingsView.swift`, `PresentationPlugins+Settings.swift`,
`BuiltinPlugins.swift`, `en.lproj/Localizable.strings`,
`zh-Hans.lproj/Localizable.strings`, `SettingsGroupPluginTests.swift`
(helper accepts the new plugin). Every source file stays under 300 lines.

### Non-goals

Remote-microphone discovery, pairing, decoding, gain range and persisted keys.
The removed Remote tab. Any other General or Integrations control. A migration.
A hint in General that the controls moved.

## Safety and failure modes

No new permission, entitlement, network call, file or persisted key. The
Bluetooth usage description and the Bluetooth permission flow are untouched.
The projection only observes remote state, as General's does today.

| Failure | Effect | Handling and evidence |
|---|---|---|
| Remote capture plugin absent (no remote provider) | Section shows, toggle disabled, no status or gain | Same behavior as General today. Real-window check with the provider absent is not planned; the condition is copied unchanged and reviewed in the diff |
| `presentation.remote-mic` disabled in `plugins.json` | Section gone. The stored switch still controls capture. The user can no longer change it in the UI until the plugin is on again | Same as disabling General today. Unit test: tab members without it |
| `presentation.integrations` disabled | Remote-mic section and Plugins remain in the tab | Unit test with the remote-mic and configuration members |
| Recovery mode | Integrations tab holds only Plugins, as before | Existing `assertRecovery` tests, run unchanged |
| A new section inside the grouped form renders flat, misaligned, or crashes for a missing environment object | Page looks broken | Real-window check in light and dark. `AppSettings` is injected at the window root, as for Integrations. If the section is wrong, stop and return to the owner |
| Existing saved profile | Values must appear in the new place | The keys are untouched. Real-window check over a seeded isolated defaults domain with the switch on and 18 dB |
| Downgrade after a hand-written `plugins.json` naming `presentation.remote-mic` | An older build does not know the id and enters recovery | The shipped default never writes this id. Documented behavior of unknown ids. Residual risk |
| Habit: the user looks in General first | The control is not there | Accepted at intent approval. No redirect hint |
| Enabling the switch in the QA clone | The clone's own bundle id may trigger a Bluetooth permission prompt and show a permission or "not connected" status | Same as the earlier General evidence (`未连接`). The status text is read as shown and the reason recorded |

## Test strategy

| Acceptance criterion | Check |
|---|---|
| General shows no remote-mic toggle, status or gain; other rows unchanged | `SettingsRemoteMicPlacementTests` reads `GeneralSettingsView.swift` through `#filePath` and fails if it mentions `remoteMicEnabled`, `remoteMicGainDB`, `remote_mic` or `remoteState`. No SwiftUI render test exists in this repo and a hosted-view accessibility walk is flaky, so this is a source guard, not a behavior test. The real-window General screenshots are the behavior evidence |
| Integrations shows the section, with the toggle disabled when there is no provider | Real-window screenshots. Unit test mounts `presentation.integrations`, `presentation.remote-mic` and `presentation.configuration` and expects one tab whose members are in that order |
| Same keys, existing tests pass unchanged | `RemoteMicPluginTests`, `RemoteSessionIngressTests`, `RemoteMicGainSettingsTests`, `SettingsProjectionTests` and `SettingsStoreTests` run without edits. In the real window, the toggle and slider are used and `defaults read` of the isolated domain shows `remoteMicEnabled` and `remoteMicGainDB` changing |
| Saved profile (on, 18 dB) shows in the new place | Isolated clone with its own bundle id, seeded with `defaults write` before launch. Screenshot shows the switch on and `18 dB`. The domain before and after is compared and every difference named |
| No string points at a missing control | Unit test: in `en` and `zh-Hans`, `settings.remote_mic_help` does not contain "above" or "上方" and contains the localized `tab.general` |
| Plugin disabled omits the section; recovery shows only Plugins | Unit tests: tab members without `presentation.remote-mic`, without `presentation.integrations`, and with only configuration. Existing recovery tests unchanged |
| Real-window screenshots, zh and en, light and dark | Isolated clone as in the consolidation change: General without the section and Integrations with it, with the six tab labels in full. Integrations top and scrolled, since the section sits below Registered apps and HTTP. Stored under `evidence/` |
| Repository checks | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`, and `bash scripts/build-app.sh --app-only` for the QA bundle |
| Real Xiaomi remote | Not available to the agent. Left to the owner after landing. Recorded in `verification.md` as residual risk unless the owner reports a result |

Isolation follows the consolidation change: `CFFIXED_USER_HOME`, a distinct bundle
id, an ad-hoc re-signed clone, and no use of `scripts/build-and-run.sh` or of the
owner's running Utter. Only the clone's own process is stopped. The owner's
defaults domain and data directory are hashed before and after.

## Rollout and rollback

- Nothing ships from this change. No tag, push or release.
- Rollback: `git revert` the code commit. The controls return to General, the
  help text returns to its old wording, and the plugin id disappears. The two
  persisted keys never changed, so no data needs repair.
- Stop conditions: the section renders wrongly in the grouped form, an existing
  remote-microphone test needs an edit to pass, any tab label clips, or the
  owner's running Utter or data is touched. In each case, stop and return to the
  owner.
