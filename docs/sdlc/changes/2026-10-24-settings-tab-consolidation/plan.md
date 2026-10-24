# Plan: Roll back to v0.0.51 and consolidate Settings tabs

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (work items A to C, the real-window safety rules and the stop conditions as written)
**Approved-date:** 2026-10-24
**Upstream:** spec.md (approved 2026-10-24)
**Risk:** High, the rollback range includes release, signing and packaging files

Work happens only in the worktree `~/.cursor/worktrees/opentype/settings-tabs`
on branch `cursor/settings-tab-consolidation`. The owner's main checkout and its
uncommitted files are not touched. Nothing is pushed, merged, tagged or released.

## Work items

### A. Rollback (spec D1, D2)

- [ ] A1. Confirm the base: `git rev-parse HEAD` is `467e934` and the only
  untracked path is this change's bundle.
- [ ] A2. `git read-tree --reset -u v0.0.51`, then commit as "Restore the product
  tree to v0.0.51". Authored content: none.
- [ ] A3. Prove commit 1: `git diff --quiet v0.0.51 HEAD` succeeds, and
  `git diff --stat HEAD~1 HEAD` reports 241 files, matching
  `git diff --stat v0.0.51 origin/main`.
- [ ] A4. Run `bash scripts/sdlc-checks.sh`. The bundle is still untracked, so
  it must still pass on the restored tree.
- [ ] A5. Commit the SDLC bundle (documents only) as commit 2.

### B. Settings consolidation (spec D3), tests first

- [ ] B1. Add `Tests/OpenTypeTests/SettingsTabLayoutTests.swift`. It fails to
  compile until B3, which is the expected red step. Cases: default list in order
  (history, general, models, style, integrations group, about); the group tab
  holds the integrations member before the configuration member; only the
  configuration member; only the integrations member; neither member; an unknown
  group id yields individual tabs; a member id maps to the group tab; an unknown
  id returns `nil`; the group label key exists in both `en` and `zh-Hans`.
- [ ] B2. Extend `BuiltinCatalogTests.testInvalidDocumentStartsOnlyRecoveryAndPreservesTheOriginalBytes`
  with the catalog check: after a failed composition, the settings tabs are
  exactly the one Integrations group tab with the configuration member only.
  Add a second case with `{"schemaVersion":1,"bundles":["desktop"],"plugins":[{"id":"presentation.remote"}]}`
  to cover a row unknown at v0.0.51, asserting recovery and unchanged bytes.
  Both use a temporary directory and an ephemeral `UserDefaults` suite.
- [ ] B3. Contracts: add `group: String? = nil` to `PresentationContribution`
  and the `group:` parameter to `PresentationPlugins.contribution(...)`. Add the
  `SettingsGroup` descriptor.
- [ ] B4. Add `SettingsTabLayout` and `SettingsTab` in `UtterPresentation`.
- [ ] B5. Add `SettingsGroupPage`. Update `SettingsView` to build tabs from
  `SettingsTabLayout`, with no `tabViewStyle` modifier.
- [ ] B6. Update `NativeDesktopHost.openSettings` to validate and normalize
  `selectedSettingsID` through `SettingsTabLayout.tabID(for:in:)`.
- [ ] B7. Convert `IntegrationsSettingsView` and `PluginConfigurationView` to
  return `Section`s without their own `Form` wrapper, form style or surface
  modifiers. Keep each view's `onAppear` hook on its own content. Register both
  with `group: SettingsGroup.integrations.id`, with orders 0 and 10.
- [ ] B8. Update `plugins.recovery` in `en` and `zh-Hans`, and
  `docs/plugin-composition.md` ("设置 → 插件" becomes "设置 → 集成"). Check
  that no other doc or string names the Plugins tab.
- [ ] B9. Keep every touched file under 300 lines. Split a file if needed.
- [ ] B10. Commit as commit 3.

### C. Verification and evidence

- [ ] C1. Automated checks, in order: `swift build`, `swift test`,
  `bash scripts/ci-basic-checks.sh`, `bash scripts/sdlc-checks.sh`.
- [ ] C2. Release-style build with `bash scripts/build-app.sh`. Check the
  artifact contents and signing outcome with the checks that exist at v0.0.51.
  If the signing identity is not configured, record that. Never fall back to
  ad-hoc signing to make it pass.
- [ ] C3. Real-window run (see below), with screenshots stored in this change's
  `evidence/` directory.
- [ ] C4. Independent verification (see below).
- [ ] C5. Fill `verification.md` with each acceptance criterion, its evidence,
  the removed features and the residual risks, then set it to
  `pending approval`.

## Verification plan

### Acceptance criteria to evidence

| Criterion | Evidence |
|---|---|
| Tree outside this change equals v0.0.51 | A3 diff checks. After commit 3, `git diff --stat v0.0.51 HEAD` lists only this bundle, Settings code, strings, docs and tests |
| Exactly six tabs in order | `SettingsTabLayoutTests` and the real-window screenshot |
| No Remote or Plugins top-level tab | Same test and screenshot |
| Merged tab keeps every control | Click-through of each Integrations and Plugins control in the real window, listed in `verification.md` |
| Six labels in full in zh and en, light and dark | Four screenshots of the tab row |
| Missing sections omit cleanly, none means no tab | `SettingsTabLayoutTests` |
| Unknown selection falls back | `SettingsTabLayoutTests` |
| Launch over v0.0.57 data does not crash | B2 tests for the recovery path, plus the manual run below |
| Checks pass | C1 and C2 output |
| Independent review | C4 report |

### Real-window run

Rules that protect the owner's session and data:

- `scripts/build-and-run.sh` ends with `pkill -x Utter`, which quits any running
  Utter, including the owner's installed app. Ask the owner before the first
  launch, and say so in the message.
- The app reads and writes `~/Library/Application Support/OpenType` and the
  `UserDefaults` domain of the real user. Record the current `uiLanguage` value
  before the run and restore it afterwards, and say so in `verification.md`.
- Light and dark are forced per process with launch arguments
  (`-AppleInterfaceStyle Dark`, or `-NSRequiresAquaSystemAppearance YES` for
  light). The global system appearance is not changed.
- For the manual recovery run, launch the binary with `HOME` pointing at a
  temporary directory holding a crafted `plugins.json`. Confirm isolation by
  checking that `OpenType` was created under the temporary `HOME`. If isolation
  cannot be shown, skip this manual run and rely on B2, and record that in the
  residual risks. The real `plugins.json` is never edited.

Steps:

1. Build and launch the development app. Open Settings.
2. Screenshot the tab row in Chinese and English, light and dark.
3. Switch language live in both directions and screenshot after each switch.
4. Visit each tab. Click through every control in Integrations and Plugins.
5. In General, confirm the remote-microphone toggle, status and gain still show.
6. Run the isolated recovery launch and screenshot the Settings window.

### Independent verification (High lane)

After C3, a verifier with no part in the implementation reviews, following
`docs/sdlc/review-policy.md`: commit 1 equality, the commit 3 diff, the removed
features list, and the rollback path. It gets read-only access to the branch,
the three SDLC documents and the evidence directory. Its findings and the
resolutions go into `verification.md`.

### Stop conditions

Stop and report to the owner, instead of working around it, if:

- six tabs still clip or overflow at 760 points in either language;
- grouped `Section`s inside one `Form` lose their grouped styling;
- any check at the v0.0.51 baseline fails for a reason unrelated to this change;
- isolation cannot be shown for a step that would write the owner's real data.

## Rollback

As in the spec: revert commit 3 to drop the consolidation, revert commit 1 to
return to `main`'s tree, or abandon the branch. No history is rewritten.
