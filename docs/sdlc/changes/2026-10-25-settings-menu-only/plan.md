# Plan: Cut the Settings window to six tabs without rolling back any feature

**Status:** pending approval            # draft | pending approval | approved | rejected | blocked
**Approved-by:** —
**Approved-date:** —
**Upstream:** spec.md (approved 2026-10-25)
**Risk:** Medium. No independent verifier is required. None is claimed.

Work happens only in the worktree `~/.cursor/worktrees/opentype/settings-menu-only`
on branch `cursor/settings-menu-only`, on top of `origin/main` (`467e934`). The
owner's main checkout and its uncommitted files are not touched. Nothing is pushed,
merged, tagged, released or installed. Draft PR #131 and the branch
`cursor/settings-tab-consolidation` are not touched.

## Work items

### A. Baseline, then tests first (red)

- [ ] A0. Hash the owner's real state before the first build or test run:
  `shasum -a 256` of the JSON files in `~/Library/Application Support/OpenType`,
  `defaults export com.opentype.voiceinput - | shasum -a 256`, and the owner's Utter
  process id. Always `cd` to the worktree explicitly; never leave the shell in the
  owner's data directory.
- [ ] A1. Baseline. `git status` is clean at the spec-approval commit. Run the tests
  this change touches or must not break: `BuiltinCatalogTests`,
  `PresentationRenderingTests`, `DesktopSettingsCommandTests`,
  `SettingsProjectionTests`, `SettingsSurfaceTests`, `UpdatePresentationTests`,
  `RemoteMicPluginTests`, `RemoteSessionIngressTests`, `RemoteMicGainSettingsTests`.
  All must pass before any edit. If one fails, stop and report.
- [ ] A2. Add `Tests/OpenTypeTests/SettingsTabLayoutTests.swift` (pure layout, page
  fixtures shaped like `main`'s eight pages, with the three members in the group at
  orders 0, 5 and 10):
  - the default composition gives six tabs in order: history, general, models, style,
    the group, about;
  - the group tab uses the group's label and symbol, and orders members by their own
    order, `integrations, remote, configuration`; a plain tab keeps its own label and
    symbol;
  - the recovery set (only `configuration`) gives one group tab with one member;
  - removing any one member, any two, or all three leaves the others in the tab, or no
    group tab;
  - `tabID(for:in:)` resolves a tab id and each member id to the group tab, and an
    unknown id to nil; `selection(_:in:)` falls back to the first tab, and to nil for
    an empty list;
  - an unknown `group` id is a plain tab;
  - `plugins.recovery` in `.english` and `.chinese` contains
    `Loc.string("settings.integrations", language:)`.
- [ ] A3. Add `Tests/OpenTypeTests/SettingsGroupPluginTests.swift`: mounts the real
  `integrations()`, `remote()` and `configuration()` registrations through
  `PluginRuntime`, with a fixture plugin providing `IntegrationServices.clients`,
  `DataServices.configuration` and `IntegrationServices.diagnostics`
  (`TestDiagnostics.service`). Cases: all three give one tab with members
  `[integrations, remote, configuration]`; each one missing; each two missing; and
  only `configuration`.
- [ ] A4. Extend `BuiltinCatalogTests` (add `@testable import UtterPresentation`; no
  existing test is edited):
  - an invalid-schema `plugins.json` starts recovery, the Integrations tab holds only
    `presentation.configuration`, `selection("presentation.models")` resolves to the
    group tab, and the file bytes are unchanged;
  - a row naming an id unknown to this build (`presentation.removed-page`, not
    `presentation.remote`, which `main` knows) does the same.
- [ ] A5. Run the new tests. Expected red step one: they do not compile, because
  `SettingsTabLayout`, `SettingsGroup` and the `group:` parameter do not exist. Confirm
  the errors are exactly those.

### B. Implementation (green)

- [ ] B1. Add the group plumbing (spec D1, D2): `group` on `PresentationContribution`
  and on `PresentationPlugins.contribution(...)`, `SettingsGroup.swift`,
  `SettingsTabLayout.swift`, `UI/SettingsGroupPage.swift`. The tests now compile.
  Expected red step two, for stated reasons only: `SettingsTabLayoutTests` pass except
  the `plugins.recovery` text test (still says "Plugins"), and
  `SettingsGroupPluginTests` and the new `BuiltinCatalogTests` cases fail because no
  page names the group yet. Confirm each failure is one of these.
- [ ] B2. Convert the three pages (spec D3): `group:` and new orders in
  `PresentationPlugins+Settings.swift` and `PresentationPlugins+Configuration.swift`;
  bare `Section`s in `IntegrationsSettingsView`, `RemoteMicSettingsView` (with
  `platform` as an `@ObservedObject` argument and the `tab.remote` header on the first
  section) and `PluginConfigurationView` (`reload()` from the description row's
  `onAppear`). The branches, rows, labels, ranges and diagnostics are copied, not
  rewritten; the diff of each is read against the old body.
- [ ] B3. `SettingsView`: build tabs from `SettingsTabLayout`, render a group tab with
  `SettingsGroupPage`, bind selection through tab ids, and remove
  `.tabViewStyle(.grouped)`. `NativeDesktopHost.openSettings()` uses
  `SettingsTabLayout.selection`.
- [ ] B4. Strings and docs (spec D6): `plugins.recovery` in `en.lproj` and
  `zh-Hans.lproj`, and `docs/plugin-composition.md` line 7. No key is added or removed.
- [ ] B5. Everything green: A2, A3, A4 tests, plus the A1 list again, with no existing
  test or file edited to make it pass. Then:
  `wc -l` of every touched Swift file stays under 300;
  `git diff --name-only origin/main` is listed and checked against the spec's file list
  and its forbidden paths (`Package.swift`, `Package.resolved`, `scripts/`, `.github/`,
  `Resources/Info.plist`, update, signing, audio and remote-capture modules);
  `rg` over `Sources`, `docs`, `README*` finds no remaining pointer to a Plugins or
  Remote tab.
- [ ] B6. Commit the code and tests as one commit, "Merge Remote and Plugins into the
  Integrations Settings tab". This is the commit to revert for rollback.

### C. Verification and evidence

- [ ] C1. Automated checks, in order: `swift build`, `swift test`,
  `bash scripts/ci-basic-checks.sh`, `bash scripts/sdlc-checks.sh`. After `swift test`,
  repeat the A0 hashes and compare. The test support code uses the real data directory
  (a pre-existing hazard), so any difference is investigated and explained, including
  the owner's own running Utter as a possible cause. The count of leftover
  `OpenTypeServiceTests-*.plist` files is reported, not listed.
- [ ] C2. Build the QA bundle from this branch with
  `bash scripts/build-app.sh --app-only`. Do not run `scripts/build-and-run.sh`, which
  ends with `pkill -x Utter`.
- [ ] C3. Build a "before" bundle: a throwaway worktree at `467e934`, built the same way.
  It is used only for the baseline screenshots below, and the worktree is removed
  afterwards.
- [ ] C4. Real-window run (below), screenshots stored in this change's `evidence/`.
- [ ] C5. Dark-mode harness (below).
- [ ] C6. Fill `verification.md`: each acceptance criterion with its evidence,
  deviations, residual risks and rollback. Set it to `pending approval`.

## Verification plan

### Acceptance criteria to evidence

| Criterion | Evidence |
|---|---|
| Six tabs, in order, no Remote and no Plugins tab | A2 test; screenshots of launches 1 and 2 |
| Every section of the three pages present, in order, unchanged | Screenshots of the Integrations tab top, middle and bottom, remote switch off and on; the B2 diff read against the old bodies; `main` baseline screenshots (C3); the existing remote-mic and settings tests unchanged and green |
| Diff scope | B5 name list checked against the spec's allow and forbid lists |
| Disabling pages; recovery | A2, A3, A4 tests; launches 3 and 4 |
| `plugins.json` still loads; selection resolves | A2 selection tests, existing composition tests, launch 3 (a valid `plugins.json` on `main` that disables `presentation.remote`) |
| Text and docs name Integrations | A2 text test; B5 `rg`; launch 4 shows the alert text |
| Labels in full, zh and en, light and dark, after live switch | Launches 1 (live switch both ways) and 2, plus the dark harness |
| Repository checks | C1 output |
| Real Xiaomi remote | Not run by the agent. Residual risk in `verification.md` unless the owner reports a result |

### Real-window run

Isolation, as proven in the earlier Settings changes:

- Copy the built `.app` to a temporary directory. Give the copy its own bundle id
  (`com.opentype.voiceinput.qa-menu-only`), re-sign it ad-hoc for this local QA copy
  only (this is not a release artifact), and launch its executable with
  `CFFIXED_USER_HOME` pointing at a temporary home, as a long-lived background shell.
- QA defaults live in the real `~/Library/Preferences` domain of the QA bundle id
  (macOS ignores `CFFIXED_USER_HOME` for preferences). Seed with `defaults write` before
  launch. `plugins.json` goes in the clone's own app-support directory under the
  temporary home. Pass `-uiLanguage zh|en`, `-hasCompletedOnboarding YES` and
  `-NSRequiresAquaSystemAppearance YES`. The system appearance is not changed.
- Before the first launch, take the A0 hashes again and list the owner's Utter process.
  After the last launch, compare. Stop only the clone's own process id. Delete the
  temporary home, the QA defaults domain and its leftover plist at the end.
- If macOS shows a Bluetooth prompt for the QA bundle id, do not grant it; record that
  it appeared and read the status line as shown.

Launches, all light (the system is light):

| # | Language | Seed | `plugins.json` | Shots and actions |
|---|---|---|---|---|
| 1 | zh | defaults, remote off | none | Tab row; Integrations top and scrolled to the end; then switch to English through the General language picker, capture the tab row and Integrations top; switch back to Chinese, capture again |
| 2 | en | `remoteMicEnabled` on, `remoteMicGainDB` 18 | none | Integrations top, the Remote section (switch, Connection, Audio with `18 dB`), and the bottom (Plugins editor with Save and Reset); click into the editor and confirm it takes focus and text, without saving; one screenshot each of Activity, General, Models, Style & Rules and About, to confirm they are unchanged and the tab row is whole |
| 3 | zh | defaults | valid file disabling `presentation.remote` | Six tabs; Integrations with no Remote section; Developer interface, Registered apps, HTTP and Plugins still present |
| 4 | en | defaults | `{"schemaVersion":999,"bundles":["desktop"]}` | The recovery alert text; the Integrations tab with only Plugins; the file's bytes unchanged |

Baseline on the `467e934` bundle, with the same isolation: launch A (zh, defaults) and
B (en, defaults): tab row at eight tabs; launch C (en, remote on, 18 dB): the Remote
tab. These show the reported problem and the content to compare launch 2 against.

In launch 2, use the slider in the Remote section and then `defaults read` the QA
domain to show `remoteMicGainDB` changed and nothing else did. The domain before and
after each launch is compared and every difference is named.

### Dark-mode harness (best effort, not committed)

A throwaway local test, deleted before the code commit, hosts the real `SettingsView`
with the real three pages in a titled `NSWindow`, sets `window.appearance` to
`.aqua` or `.darkAqua`, and captures that window with `screencapture -l`. Step one is
calibration: the `.aqua` capture must match launch 1 and 2 (same tab labels in the
title bar, same page layout). If it matches, the `.darkAqua` captures in zh and en are
used as dark evidence and labeled as harness captures, not the full app. If it does
not match, or the window server or capture permission is unavailable, the dark gap is
recorded and the owner is asked before the system appearance is touched.

### Stop conditions

Stop and report to the owner, instead of working around it, if:

- a section renders flat, misaligned, loses state or crashes in the grouped form;
- the Plugins editor cannot take focus or does not load its text;
- any tab label clips or the automatic style overflows, in either language, including
  after the live switch;
- an existing test needs an edit to pass, or the A1 baseline fails for a reason
  unrelated to this change;
- the diff leaves the spec's file list;
- isolation cannot be shown, or the owner's running Utter or data is touched.

## Human gates

- Approval of this plan, before any code changes.
- Approval of `verification.md`, after the evidence is in.
- Closing draft PR #131, pushing this branch, opening a PR, merging, tagging,
  releasing, or replacing the owner's installed Utter: each is a separate decision,
  not part of this change.
- Changing the system appearance to get real dark-mode windows, if the harness is not
  faithful.
- Testing with a real Xiaomi remote: the owner's, if wanted.

## Rollback

As in the spec: `git revert` the code commit from B6. The eight tabs and
`.tabViewStyle(.grouped)` return. No persisted key changed, so no data needs repair.
The documents can stay as a record.
