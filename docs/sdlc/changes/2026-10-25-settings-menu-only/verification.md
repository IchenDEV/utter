# Verification: Cut the Settings window to six tabs without rolling back any feature

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (the verification record as written, including its deviations, disclosed input mishaps and residual risks; pushing, opening or closing a PR, merging, tagging, releasing and replacing the installed Utter remain separate decisions)
**Approved-date:** 2026-10-25
**Upstream:** plan.md (approved 2026-10-25)
**Risk:** Medium. No independent verifier was required and none was used. Every visual claim below was reviewed by the implementer only.

Nothing was pushed, merged, tagged, released or installed. The work is on the local
branch `cursor/settings-menu-only`, in the worktree
`~/.cursor/worktrees/opentype/settings-menu-only`, cut from `467e934`. Draft PR #131
and `cursor/settings-tab-consolidation` were not touched.

## Result in one paragraph

On top of the current product, the Settings window has six tabs: Activity, General,
Models, Style & Rules, Integrations, About. The Integrations tab is one scrolling
page: Developer interface, Registered apps, HTTP, Remote, Plugins. Every row of
the old Integrations, Remote and Plugins pages is there and works; Sparkle,
signing, the Remote diagnostics and all other features are as on `main`. The tab
style is automatic again, and all six labels show in full in Chinese and English,
after a live language switch in both directions, and in a dark-appearance harness.
All automated checks pass. Two things are weaker than a full real-window check: the
dark captures come from a harness window, not the full app, and mouse-wheel
scrolling could not be injected (scrolling was driven through the scroll bar). The
voice key of the real remote was not pressed.

## Commits

| Commit | Content |
|---|---|
| `f0a6d96`, `3da1d16` | Intent, and its approval record |
| `16c1efe`, `9a7fde9` | Spec, and its approval record |
| `3be8989`, `f7919f4` | Plan, and its approval record |
| `47a8d1f` | Code, strings, docs and tests: the commit to revert for rollback |
| this commit | Evidence and this file |

`47a8d1f` adds `SettingsGroup.swift` (13 lines), `SettingsTabLayout.swift` (47),
`UI/SettingsGroupPage.swift` (19), `SettingsTabLayoutTests.swift` (120) and
`SettingsGroupPluginTests.swift` (79); and edits `PresentationServices.swift`,
`PresentationPlugins.swift`, `PresentationPlugins+Settings.swift`,
`PresentationPlugins+Configuration.swift`, `IntegrationsSettingsView.swift` (99),
`RemoteMicSettingsView.swift` (124), `SettingsView.swift` (57),
`NativeDesktopHost+Windows.swift` (99), `BuiltinCatalogTests.swift` (106), both
`Localizable.strings` and `docs/plugin-composition.md`. Every Swift file is under
300 lines. No existing test or test file other than `BuiltinCatalogTests.swift`
(two cases added, none edited) was touched.

Diff scope: `git diff --name-only 467e934 HEAD` outside this bundle lists 17 files,
all in the list above. None is `Package.swift`, `Package.resolved`, `scripts/`,
`.github/`, `Resources/Info.plist`, or in the update, audio, remote-capture or Mac
services modules. A first scope check against `origin/main` ran while it was still
`467e934` and gave the same list. `origin/main` has since moved to `7be691a`
(PR #132: delivery code and tests in the Mac services module, both READMEs, and one
SDLC bundle; 8 commits). None of them touch the presentation, presentation-contract
or string files, and `git merge-tree` reports a clean merge with this branch.

## Test-first record

- A1 baseline, before any edit: 9 suites (`BuiltinCatalogTests`,
  `PresentationRenderingTests`, `DesktopSettingsCommandTests`,
  `SettingsProjectionTests`, `SettingsSurfaceTests`, `UpdatePresentationTests`,
  `RemoteMicPluginTests`, `RemoteSessionIngressTests`, `RemoteMicGainSettingsTests`):
  30 tests, 0 failures.
- Red step one: with the new tests in place the test target did not compile; the
  errors were `cannot find 'SettingsGroup'`, `cannot find 'SettingsTabLayout'` and
  `cannot find type 'SettingsTab'`, and the key-path errors that follow from them.
- Red step two, with the group plumbing present and the pages, strings and views
  still as on `main`: 21 tests ran and 17 assertions failed, all for the stated
  reasons. This run was repeated at verification time by restoring the six
  `main` versions of two page-registration files, two page views and two
  string files with `git checkout 467e934 -- …`, running the three suites, and
  restoring `HEAD` (`git diff HEAD` over `Sources`, `Tests` and the docs file is
  empty again). The log is not kept. `SettingsTabLayoutTests`, 12 tests, 2
  failures: all cases passed except the `plugins.recovery` text case (it still said
  "Open Plugins" and "插件组合页"). `SettingsGroupPluginTests`, 4 tests, 11
  failures: the mounted pages were still three separate tabs
  (`presentation.remote`, `presentation.integrations`, `presentation.configuration`),
  the "no member means no tab" case passed. `BuiltinCatalogTests`, 5 tests, 4
  failures: the two new recovery cases saw `presentation.configuration` as its own
  tab instead of `presentation.group.integrations`.
- Green, same 9 suites plus the new ones: 48 tests (30 + 12 layout + 4 plugin-group
  + 2 recovery), 0 failures. No existing test was edited.

## Automated checks

| Check | Result | Notes |
|---|---|---|
| `swift build` | Pass | |
| `swift test` | Pass | 531 tests, 18 skipped, 0 failures |
| `bash scripts/ci-basic-checks.sh` | Pass | |
| `bash scripts/sdlc-checks.sh` | Pass | |
| `bash scripts/build-app.sh --app-only` | Pass | "Release artifact verification passed". The QA copy was re-signed ad hoc under a different bundle id for local QA only; it is not a release artifact |
| Owner state | Unchanged | SHA-256 of `dictionary.json`, `edit_rules.json` and `input_history.json` and of `defaults export com.opentype.voiceinput` identical before the first test run and after the last launch and the red-step re-run. The owner's Utter (pid 33917) ran throughout and was never signalled. `swift test` left 30 more `OpenTypeServiceTests-*.plist` files in `~/Library/Preferences` (6,945 to 6,975), the known pre-existing hazard |

## Acceptance criteria to evidence

Screenshots are in `evidence/`. "Real" means the full app window of the isolated
clone, light appearance. "Harness" means the real `SettingsView` with the real three
pages in a titled window with an explicit appearance (see below).

| Criterion | Result | Evidence |
|---|---|---|
| Six tabs in order, no Remote, no Plugins | Met | `SettingsTabLayoutTests.testDefaultCompositionHasSixTabsInOrder`; AX count of tab buttons was 6 in launches 1 and 3; `real-light-zh-general.png`, `real-light-en-tab-*.png` |
| Every section of the three pages present, in order, unchanged | Met | Order Developer interface, Registered apps, HTTP, Remote, Plugins: `real-light-zh-integrations-top.png`, `real-light-zh-integrations-bottom.png`, `real-light-en-remote-on-integrations-*.png`. Against `main`'s own pages (`before-main-en-remote-tab-on.png`, `before-main-en-integrations-tab.png`, `before-main-en-plugins-tab.png`): same rows and texts, including Connection (Connected, RC003, System Bluetooth connection, Standard, Reconnect, Open Bluetooth Settings), Audio (Gain 18 dB, Last recording), usage and troubleshooting notes. One intended difference: the switch block now has the header "Remote"/"遥控器" |
| Features behave | Met for what was exercised | Gain slider moved to 10 and the QA domain's `remoteMicGainDB` read 10, restored to 18 (`real-light-en-remote-gain-moved-to-10.png`). The Plugins editor loaded the document, took focus and accepted an edit (not saved; no `plugins.json` was created). Switch state 1 and 18 dB seeded before launch showed correctly |
| Diff scope | Met | See Commits |
| Disabling pages; recovery | Met | Unit tests for all seven non-empty subsets, the real plugins mounted through the runtime, and the recovery set. Real: `presentation.remote` disabled in `plugins.json` gives six tabs and an Integrations tab without Remote and with Developer interface, Registered apps, HTTP and Plugins (`real-light-zh-remote-plugin-disabled-*.png`), file bytes unchanged. Invalid `plugins.json` (schema 999): Settings opens on its own with a single Integrations tab holding only Plugins, and the alert names Integrations (`real-light-en-recovery-*.png`), file bytes unchanged |
| `plugins.json` still loads; selection resolves | Met | The disabling file above is valid on `main` and loaded. `SettingsTabLayoutTests` cover member id, tab id, unknown id and an empty list; `BuiltinCatalogTests` cover recovery with an invalid schema and with an id unknown to this build |
| Text and docs name Integrations | Met | Unit test on both languages; alert screenshot (English). `rg` for "Plugins tab", "Remote tab", "插件页", "遥控器页", "Open Plugins", "设置 → 插件", "插件组合页" over `Sources`, `docs` (outside earlier change records) and the READMEs found nothing |
| Labels in full, zh and en, light and dark, live switch | Met, dark by harness | Real light: Chinese start, live switch to English (`real-light-live-switch-to-en-integrations-top.png`) and back (`real-light-live-switch-back-to-zh-integrations-bottom.png`), English with remote on. Dark: `harness-dark-zh-*.png`, `harness-dark-en-*.png` |
| Repository checks | Met | See Automated checks |
| Real Xiaomi remote | Partly | The owner's real remote was connected to the Mac, and the clone showed "Connected: 小米蓝牙语音遥控器", model RC003, found via the system Bluetooth connection, standard decoding. The voice key was not pressed and no recording was made, so live capture is untested |

### Dark-appearance harness

The system is in light mode and a process cannot be forced dark from outside (known
from the earlier change). A throwaway local test hosted the real `SettingsView`, the
real `integrations`, `remote` and `configuration` registrations (through the plugin
runtime, with fixture services) and plain placeholders for the other five tabs, in
a titled `NSWindow` with `appearance` set to `.aqua` or `.darkAqua`, and captured the
window with `screencapture -l`. Calibration passed: the `.aqua` capture matches the
real clone at the same language, with the same tab strip geometry and the same page
layout (`harness-light-zh-integrations-top.png` against
`real-light-zh-integrations-top.png`, `harness-light-en-integrations-top.png` against
`real-light-en-remote-on-integrations-top.png`). The harness has no remote provider,
so its switch is disabled and its status reads "not connected", which is the only
difference. The test file was deleted before the code commit and is not in the repo.
The system appearance was not changed.

## Deviations from the plan

1. **Baseline build commit.** The "before" bundle was built from `origin/main` as
   it stood when I made the worktree, `7be691a` (v0.0.57), not `467e934`: `main`
   moved in between. The eight new commits change no presentation, contract or
   string file, so the Settings window is the same. Its packages were copied from
   this worktree's `.build` after a network failure cloning the `mlx` submodule;
   the package pins are identical.
2. **The reported look was not reproduced.** `main` already forces the grouped tab
   style, and in this clone its eight-tab window shows a tab strip under the title
   (`before-main-zh-eight-tabs.png`). I cannot tell from that whether it is the look
   you called broken. The new window is six tabs in the automatic style, in the
   title bar (`real-light-zh-general.png`). Please compare the two.
3. **Scrolling and editing.** Mouse-wheel events posted to the clone were not
   delivered, so the page was scrolled by setting the scroll bar through
   accessibility. Typing into the Plugins editor was replaced by an accessibility
   value edit, to avoid sending keystrokes to whichever app is in front.
4. **Dark by harness**, as above, instead of full-app windows.
5. **Two input mishaps, disclosed.** (a) One coordinate click on the language picker
   was followed by the clone's Settings window closing and, in a later full-screen
   capture, an unrelated Finder window; other agents are active on this machine and
   the cause is unknown. The click's reported target was the clone's picker. (b) One
   HID-level scroll event was posted at a screen point while another app was in
   front, so it may have scrolled a window other than the clone; I stopped using that
   path. Both full-screen captures were deleted because they show your desktop.

## Residual risks

- The dark captures are harness windows, not the full app.
- Real mouse-wheel scrolling of the long Integrations page and real keyboard typing in
  the Plugins editor were not exercised; the page and editor otherwise behave as
  scroll views and text views.
- Deep links and selection by `presentation.remote` land at the top of the
  Integrations tab, not at the Remote section. People used to a Remote tab must find
  the section.
- Live capture from the remote's voice key, and the clone's behavior with the switch
  on alongside your running Utter, were not exercised beyond the connected status.
- This branch is 8 commits behind `origin/main`; the merge is clean today.
- Large accessibility text sizes were not checked.

## Rollback

`git revert 47a8d1f`. The eight tabs and `.tabViewStyle(.grouped)` return, the
recovery alert and the docs line return to "Plugins". No persisted key, plugin id or
file format changed, so nothing needs repair. The documents and evidence can stay as
a record.

## Human gates still open

- Closing draft PR #131 (asked separately, not done).
- Pushing this branch, opening a PR, merging, tagging, releasing, or replacing your
  installed Utter.
