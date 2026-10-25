# Plan: Move the Xiaomi remote microphone controls into Integrations

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (work items A to C, the real-window safety rules and the stop conditions as written)
**Approved-date:** 2026-10-25
**Upstream:** spec.md (approved 2026-10-25)
**Risk:** Medium. No independent verifier is required. None is claimed.

Work happens only in the worktree `~/.cursor/worktrees/opentype/settings-tabs`
on branch `cursor/settings-tab-consolidation`, on top of `86b74f4`. The owner's
main checkout and its uncommitted files are not touched. Nothing is pushed,
merged, tagged or released.

## Work items

### A. Tests first (red)

- [ ] A1. Baseline. `git status` is clean. Run the tests this change touches or
  must not break: `SettingsGroupPluginTests`, `SettingsTabLayoutTests`,
  `BuiltinCatalogTests`, `RemoteMicPluginTests`, `RemoteSessionIngressTests`,
  `RemoteMicGainSettingsTests`, `SettingsProjectionTests`. All must pass before
  any edit. If one fails, stop and report.
- [ ] A2. Extend `SettingsGroupPluginTests`. The fixture also provides
  `IntegrationServices.diagnostics` (using `TestDiagnostics.service`), and the
  catalog gains `PresentationPlugins.remoteMic()`. New cases:
  - mounting integrations, remote-mic and configuration gives one tab, members
    `[presentation.integrations, presentation.remote-mic, presentation.configuration]`;
  - without `presentation.remote-mic`, members are integrations then
    configuration (the shape of the existing test stays valid);
  - without `presentation.integrations`, members are remote-mic then configuration;
  - with only remote-mic, the group tab exists with that one member.
  The new cases fail to compile until B2. That is the expected red step.
- [ ] A3. Add `Tests/OpenTypeTests/SettingsRemoteMicPlacementTests.swift`:
  - the source guard: it finds the repository root from `#filePath`, reads
    `Sources/UtterPresentation/UI/GeneralSettingsView.swift`, fails with a clear
    message if the file cannot be read, and fails if the text contains
    `remoteMicEnabled`, `remoteMicGainDB`, `remote_mic` or `remoteState`;
  - the help text: for `.english` and `.chinese`, `settings.remote_mic_help`
    contains `Loc.string("tab.general", language:)` and contains neither
    "above" nor "上方".
  Both fail on the current tree: the block is still in General and the help text
  still says "above".
- [ ] A4. Run the new tests and confirm they fail for the stated reasons, not for
  a typo.

### B. Implementation (green)

- [ ] B1. Add `Sources/UtterPresentation/UI/RemoteMicSettingsView.swift` (spec D2).
  The rows are copied from `remoteMicControls` with no change in label keys,
  disabled condition, slider range, step or `N dB` label. The view gets
  `AppSettings` from the environment and `PlatformProjection` as an
  `@ObservedObject` argument.
- [ ] B2. Add `PresentationPlugins.remoteMic()` in
  `PresentationPlugins+Settings.swift` (spec D1): id `presentation.remote-mic`,
  order 5, group `SettingsGroup.integrations.id`, `platformRequirements`.
  Add it to the presentation list in `BuiltinPlugins.swift`, right after
  `integrations()`. Do not touch `BuiltinCompositions.recoveryIDs`.
- [ ] B3. Remove `remoteMicControls` and its call from `GeneralSettingsView.swift`
  (spec D3). Nothing else in that file changes.
- [ ] B4. Change `settings.remote_mic_help` in `en.lproj` and `zh-Hans.lproj`
  to the wording in spec D4. No key is added or removed.
- [ ] B5. Run `A2` and `A3` tests: all green. Run the A1 list again: unchanged and
  green, with no test edited to make it pass.
- [ ] B6. Check `wc -l` of every touched Swift file stays under 300, and that
  `git diff --stat` lists only the files named in the spec.
- [ ] B7. Commit the code and tests as one commit, "Move the remote mic controls
  into the Integrations tab". This is the commit to revert for rollback.

### C. Verification and evidence

- [ ] C1. Automated checks, in order: `swift build`, `swift test`,
  `bash scripts/ci-basic-checks.sh`, `bash scripts/sdlc-checks.sh`.
  Before `swift test`, hash the owner's real data under
  `~/Library/Application Support/OpenType` and the owner's defaults domain
  `com.opentype.voiceinput`. Compare afterwards. The test support code uses the
  real data directory (a pre-existing hazard); any difference is investigated
  and explained, including the owner's own running Utter as a possible cause.
- [ ] C2. Build the QA bundle with `bash scripts/build-app.sh --app-only`. Do not
  run `scripts/build-and-run.sh`, which ends with `pkill -x Utter`.
- [ ] C3. Real-window run (below), with screenshots stored in this change's
  `evidence/` directory.
- [ ] C4. Fill `verification.md`: each acceptance criterion with its evidence,
  deviations, residual risks and rollback. Set it to `pending approval`.

## Verification plan

### Acceptance criteria to evidence

| Criterion | Evidence |
|---|---|
| General has no remote-mic controls; other rows unchanged | A3 source guard, B3 diff, General screenshots |
| Integrations shows the section; toggle disabled when no provider | Placement unit tests, Integrations screenshots. The no-provider case is the same `.disabled` condition as before, checked by reading the B1 diff against the old block |
| Same keys; existing tests pass unchanged | A1 list before and after, with no edits to those files; `defaults read` of the QA domain after using the toggle and slider |
| Saved profile (on, 18 dB) shows in the new place | QA clone seeded before launch; screenshot shows the switch on and `18 dB`; domain before and after compared |
| No string points at a missing control | A3 help-text test |
| Plugin disabled omits the section; recovery shows only Plugins | A2 cases; `BuiltinCatalogTests` recovery cases unchanged and green |
| Real-window zh and en, light and dark, six labels in full | Screenshots below |
| Repository checks | C1 output |
| Real Xiaomi remote | Not run by the agent. Residual risk in `verification.md` unless the owner reports a result |

### Real-window run

Isolation, as proven in the Settings consolidation change:

- Copy the built `.app` to a temporary directory. Give the copy its own bundle
  id (`com.opentype.voiceinput.qa-remote-mic`), re-sign it ad-hoc for this local
  QA copy only, and launch its executable with `CFFIXED_USER_HOME` pointing at a
  temporary home. The launch runs as a long-lived background shell.
- Seed the QA defaults by writing the plist at
  `<temp home>/Library/Preferences/<qa bundle id>.plist` before the first
  launch, then confirm the seeded values show in the window before relying on
  them. Pass `-uiLanguage`, `-hasCompletedOnboarding YES` and the appearance
  arguments (`-AppleInterfaceStyle Dark`, or `-NSRequiresAquaSystemAppearance YES`
  for light) as launch arguments. The system appearance is not changed.
- Before the first launch, hash the owner's `OpenType` data files and defaults
  domain, and list the owner's Utter process. After the last launch, compare.
  Stop only the clone's own process id. Delete the temporary home and the QA
  defaults domain at the end.
- If macOS shows a Bluetooth permission prompt for the QA bundle id, do not
  grant it. Choose Don't Allow, record that it appeared, and read the status
  line as shown.

Launches (each shows one language and appearance):

| Launch | Language | Appearance | Seed |
|---|---|---|---|
| 1 | zh | dark | `remoteMicEnabled` on, 18 dB |
| 2 | en | light | `remoteMicEnabled` on, 18 dB |
| 3 | zh | light | `remoteMicEnabled` on, 18 dB |
| 4 | en | dark | none (default off) |

Per launch, screenshot General (the Audio section visible, without the remote
rows), the Integrations tab top, and the Integrations tab scrolled to the
remote-microphone section. The tab row must show all six labels in full.
In launch 4, turn the switch on, move the slider, then `defaults read` the QA
domain to show `remoteMicEnabled` and `remoteMicGainDB` changed. Also confirm
the help text reads correctly in both languages in launches 1 and 2.

### Stop conditions

Stop and report to the owner, instead of working around it, if:

- the new section renders flat, misaligned or crashes in the grouped form;
- an existing remote-microphone or settings test needs an edit to pass;
- any tab label clips, in either language;
- the A1 baseline fails for a reason unrelated to this change;
- isolation cannot be shown, or the owner's running Utter or data is touched.

## Human gates

- Approval of this plan, before any code changes.
- Approval of `verification.md`, after the evidence is in.
- Pushing, opening a PR, merging, tagging, releasing, or replacing the owner's
  installed Utter: each is a separate decision, not part of this change.
- Testing with a real Xiaomi remote: the owner's, if wanted.

## Rollback

As in the spec: `git revert` the code commit from B7. The controls return to
General and the help text to its old wording. The persisted keys never changed,
so no data needs repair. The documents can stay as a record.
