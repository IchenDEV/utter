# Verification: Move the Xiaomi remote microphone controls into Integrations

**Status:** pending approval            # draft | pending approval | approved | rejected | blocked
**Approved-by:** —
**Approved-date:** —
**Upstream:** plan.md (approved 2026-10-25)
**Risk:** Medium. No independent verifier was required and none was used. Every visual claim below was reviewed by the implementer only.

Nothing was pushed, merged, tagged or released. The work is on the local branch
`cursor/settings-tab-consolidation`, in the worktree `~/.cursor/worktrees/opentype/settings-tabs`.

## Result in one paragraph

The Xiaomi remote-microphone controls now live in the Integrations tab, between
HTTP and Plugins, as their own plugin `presentation.remote-mic`. General no longer
has them. The toggle, connection line and gain slider behave as before and write
the same two settings keys. The help text now points at General instead of
"above". All automated checks pass. **Not met: dark-appearance screenshots**,
because the machine is in light mode and the dark attempts did not take effect
(see "Open items for the owner"). The real Xiaomi remote was not tested.

## Commits

| Commit | Content |
|---|---|
| `ad02e88`, `86b74f4`, `a6d046c`, `373db40` | Intent, spec, plan and their approval records, documents only |
| `e340695` | Code, strings and tests: the commit to revert for rollback |
| this commit | Evidence and this file |

Files in `e340695`: new `UI/RemoteMicSettingsView.swift` (39 lines) and
`Tests/OpenTypeTests/SettingsRemoteMicPlacementTests.swift`; edited
`GeneralSettingsView.swift` (279 to 249 lines), `PresentationPlugins+Settings.swift`
(83 lines), `BuiltinPlugins.swift`, both `Localizable.strings`, and
`SettingsGroupPluginTests.swift`. `git diff --stat` for that commit lists exactly
these and nothing else. No existing remote-microphone or settings test file was edited.

## Test-first record

- A1 baseline before any edit: 28 tests in `SettingsGroupPluginTests`,
  `SettingsTabLayoutTests`, `BuiltinCatalogTests`, `RemoteMicPluginTests`,
  `RemoteSessionIngressTests`, `RemoteMicGainSettingsTests` and
  `SettingsProjectionTests`: all passed.
- Red step: with the new tests in place, the test target did not compile
  (`type 'PresentationPlugins' has no member 'remoteMic'`). With the group test
  file set aside, `SettingsRemoteMicPlacementTests` failed for the stated reasons: General
  still contained `remoteMicEnabled`, `remoteMicGainDB`, `remote_mic` and
  `remoteState`, and the help text still said "selected above" / "上方" without
  naming General.
- After the change the same seven suites plus the new one: 34 tests, 0 failures.
  The four new `SettingsGroupPluginTests` cases cover member order
  (integrations, remote-mic, configuration), without remote-mic, without
  integrations, and remote-mic alone.

## Automated checks

| Check | Result | Notes |
|---|---|---|
| `swift build` | Pass | |
| `swift test` | Pass: 493 executed, 18 skipped, 0 failures, exit 0 | The 88 `error:` lines in the log are Contacts/AddressBook connection noise from existing tests, with no failing test case |
| `bash scripts/ci-basic-checks.sh` | Pass | Includes string key parity and `plutil -lint` on both strings files |
| `bash scripts/sdlc-checks.sh` | Pass | |
| `bash scripts/build-app.sh --app-only` | Pass, exit 0 | Printed "Release artifact verification passed". The app is signed **ad-hoc, locally**. This is a QA build, not a release candidate |

## Acceptance criteria and evidence

Screenshots are in `evidence/`. All of them are **light** appearance. The window
captures were made with `screencapture -l` of the clone's Settings window.

| Criterion | Result | Evidence |
|---|---|---|
| General has no remote-mic toggle, status or gain; other rows unchanged | Met | `SettingsRemoteMicPlacementTests` source guard; `04`, `06`, `08`. `06` and `08` were taken with the saved profile "on, 18 dB", where the old General page would have shown the status and gain rows |
| Integrations shows the section: toggle; when on, connection line and gain 0 to 24 dB; toggle disabled when there is no provider | Met, except the disabled case | `01` (off), `02` (on: "Connection: Searching for the remote…", "Gain 12 dB"). The no-provider case was **not exercised**: the clone always has the provider. The `.disabled(!platform.hasRemoteProvider)` line was copied unchanged and read against the old block in the diff |
| Same keys; existing remote-mic tests pass unchanged | Met | Test files untouched; `RemoteMicPluginTests`, `RemoteSessionIngressTests`, `RemoteMicGainSettingsTests`, `SettingsProjectionTests` pass; `SettingsStoreTests` passes in the full run. In the clone, switching on wrote `remoteMicEnabled = 1` and the slider changed `remoteMicGainDB` from 12 to 18 (read back with `defaults read` of the QA-only domain; `03` shows 18 dB) |
| Saved profile (on, 18 dB) shows in the new place; nothing else changes | Met, in zh and en | `05` (zh), `07` (en). `evidence/qa-defaults-diff.txt`: after minus before, the only additions are the window-frame autosave and the generated HTTP token; `remoteMicEnabled` and `remoteMicGainDB` are unchanged |
| No string refers to a control "above" | Met | `testHelpTextPointsAtGeneralNotAtAControlAbove`: en "...chosen in General.", zh "...在“通用”页选择的 Mac 麦克风。", both contain the localized `tab.general`. Visible in `01` and `05` |
| Plugin disabled omits the section; recovery shows only Plugins | Met | Unit tests for each member combination; `BuiltinCatalogTests` recovery cases unchanged and passing |
| Real-window screenshots, zh and en, light and dark, six labels in full | **Partly met** | zh light (`05`, `06`) and en light (`01` to `04`, `07`, `08`): the tab row shows all six labels in full in every capture. **Dark: none**, see below |
| `sdlc-checks`, `ci-basic-checks`, `swift test`; placement tests exist | Met | Tables above |
| Real Xiaomi remote | **Not run** | Residual risk. The status line did show "Searching for the remote…" with the switch on, so scanning started, and no Bluetooth permission prompt appeared |

## Removed from General, added to Integrations

- Removed from General: nothing but the remote-mic rows. Hotkey, mode, microphone,
  recognition language, streaming, sensitivities and the sections below are as before.
- Added to Integrations: one section titled "Xiaomi remote wireless mic" /
  "小米遥控器无线麦", with the same labels, help text (reworded), range and step.
- Added to the composition: plugin id `presentation.remote-mic`. It is on by
  default through the `desktop` bundle, is not in the recovery set, and can be
  disabled with a `plugins.json` row.

## Method of the real-window run

An isolated clone of `dist/Utter.app` was used, so the owner's running Utter (PID
33917) was never stopped. The clone is a copy with `CFBundleIdentifier`
`com.opentype.voiceinput.qa-remote-mic`, re-signed ad-hoc with the original
entitlements and hardened runtime, and started directly with `CFFIXED_USER_HOME`
pointing at a temporary directory. Settings was opened through the clone's own
menu bar item (selected by unix id, so the owner's Utter was never addressed). The
switch was clicked with a pointer click; the slider was set with an accessibility
`set value`, not a drag. Only the clone's own process was stopped each time.

Isolation evidence:

- SHA-256 of the owner's `dictionary.json`, `edit_rules.json` and
  `input_history.json`, and of the exported `com.opentype.voiceinput` defaults
  domain, was taken before the first test run and compared after the last clone:
  all identical. The owner's Utter was still PID 33917. No `plugins.json` exists
  in the owner's data directory.
- The QA defaults domain was deleted afterwards, and its empty plist file
  removed. The clone's temporary data directories were deleted.

## Deviations from the plan

1. **Seeding.** The plan said to seed a plist under the temporary home. The QA
   defaults domain actually lives in the real `~/Library/Preferences` (the
   preferences daemon ignores `CFFIXED_USER_HOME`; the data directory honors it).
   The domain was seeded with `defaults write` on the QA-only bundle id, and
   deleted afterwards. The owner's own domain was not written.
2. **Launch matrix and appearance.** The plan listed four launches. The machine is
   in light mode (Auto appearance, currently light, `AppleInterfaceStyle`
   absent), and dark could not be forced per process: the launch argument
   `-AppleInterfaceStyle Dark` and a per-domain `AppleInterfaceStyle = Dark` key
   both left the window light. Changing the system appearance was excluded by the
   plan. The launches that ran: en light with no seed (switch off, on, slider
   12 to 18); zh light seeded on and 18 dB; en light seeded on and 18 dB.
3. **No scrolled screenshot.** In the 680-point window the new section is fully
   visible without scrolling (Plugins starts just below it), so the planned
   scrolled capture was not needed.
4. **Slider by accessibility, not by drag.** Both paths go through the same
   binding. The window showed the new value a few seconds after the `set value`.
5. **A stray file was created and removed.** The shell's working directory was the
   owner's data directory when the clones were launched, and a clone created an
   empty `default.profraw` there at 18:57. It was not in the earlier baseline. I
   deleted that one file. The hash comparison covers the three data files and the
   defaults domain, which that file did not touch, and was repeated after the
   removal with identical results.

## Observations outside this change

- **Tests write to real locations (pre-existing).** `swift test` rewrote
  `dictionary.json` and `edit_rules.json` in the owner's data directory (the
  modification times changed to the test run, the SHA-256 did not), and left new
  `OpenTypeServiceTests-*.plist` files in `~/Library/Preferences`: about 30 from
  this session's runs (28 new files counted after the full run), 6,930 of that
  name in total. Not fixed here. It is worth its own change.
- **The owner's own setting is on.** At the baseline the owner's `remoteMicEnabled`
  was 1, so the owner's Utter was already scanning for the remote. The clone also
  scanned for a few minutes with the switch on. Neither found a remote. If one had
  been awake nearby, the two processes could have competed for it. The owner's
  value was not changed.

## Open items for the owner

1. **Dark appearance.** Producing dark screenshots needs the system appearance
   flipped for about a minute (it would flip back), or waiting until Auto switches
   it. The new section uses the same `Section`, `Toggle` and `Slider` components as
   its neighbors in the same form, so the risk is low, but the criterion says
   dark. Decide: flip temporarily, wait for the system, or accept the gap.
2. **Real Xiaomi remote.** Turn it on in Integrations with the remote nearby, and
   check the connection line.
3. **Landing.** Pushing, a PR, merging, tagging, releasing, or replacing the
   installed Utter are separate decisions. This branch is stacked on the
   unmerged consolidation change.

## Residual risks

- Dark appearance not captured (above).
- The toggle's disabled state without a remote provider was not exercised.
- Disabling `presentation.remote-mic` hides the control while the stored switch
  keeps driving capture, the same as disabling General did before.
- Users who look in General first will not find the controls. No redirect hint, as agreed.
- A hand-written `plugins.json` naming `presentation.remote-mic` makes older builds
  enter recovery. The shipped default never writes that id.
- The QA app is an ad-hoc local build. No release artifact, DMG, checksum or
  signing path was exercised.

## Rollback

`git revert e340695`. The controls return to General and the help text to its old
wording. The two persisted keys never changed, so no data needs repair. The
documents and evidence can stay as a record.
