# Verification: Roll back to v0.0.51 and consolidate Settings tabs

**Status:** approved            # draft | pending approval | approved | rejected | blocked
**Approved-by:** User, explicit chat decision: 批准 (the verification record, its deviations and its residual risks as written; merging, tagging and releasing remain separate decisions)
**Approved-date:** 2026-10-25
**Upstream:** plan.md (approved 2026-10-24)
**Risk:** High, the rollback range includes release, signing and packaging files

Nothing was pushed, merged, tagged or released. The work lives on the local branch
`cursor/settings-tab-consolidation`, in the worktree `~/.cursor/worktrees/opentype/settings-tabs`.

## Result in one paragraph

The Settings window now has six tabs (Activity, General, Models, Style & Rules,
Integrations, About) on the v0.0.51 tree. Integrations and Plugins are stacked on
one scrolling page. The automatic tab style fits six tabs at 760 points in
Chinese and English, in light and dark, so `.tabViewStyle(.grouped)` is not
needed. No stop condition from the plan was hit. Open items for the owner are in
"Residual risks" and "Deviations from the plan".

## Commits

| Commit | Content |
|---|---|
| `7c80d2e` | "Restore the product tree to v0.0.51" (`git read-tree --reset -u v0.0.51`, no authored content) |
| `2d45a34` | SDLC bundle, documents only |
| `21933f2` | Settings consolidation: code, strings, tests, `docs/plugin-composition.md` |
| `7454531` | Real-window evidence (24 screenshots) |
| next | Test-only: assert the exact Integrations label in both languages (independent verifier finding 4) |
| this commit | `verification.md` |

## Automated checks

| Check | Result | Notes |
|---|---|---|
| `swift build` | Pass | |
| `swift test` | Pass: 487 executed, 18 skipped, 0 failures | Run by the implementer at `21933f2`. Re-run by the independent verifier at `7454531` with the same counts. CoreData and Contacts error lines in the log are environmental noise |
| `swift test --filter SettingsTabLayoutTests` | Pass: 11 of 11 | Re-run after the test-only change that followed the verifier |
| `bash scripts/ci-basic-checks.sh` | Pass | Implementer and verifier |
| `bash scripts/sdlc-checks.sh` | Pass | Re-run on the commit that contains this file |
| Release-style build | **Partial.** `bash scripts/build-app.sh --app-only` exited 0 and printed "Release artifact verification passed", `valid on disk` and `satisfies its Designated Requirement` | The app was signed **ad-hoc, locally**. See Deviation 2. This artifact is not a release candidate |

## Acceptance criteria and evidence

Screenshots are in `evidence/`. "Dark" is the machine's current appearance. "Light"
was forced per process with `-NSRequiresAquaSystemAppearance YES`. The global
appearance was not changed.

| Criterion | Result | Evidence |
|---|---|---|
| Tree outside the Settings change equals v0.0.51 | Met | `git diff --quiet v0.0.51 7c80d2e` succeeds. The 241-file set of `git diff --name-only v0.0.51 origin/main` equals that of `467e934 7c80d2e` (verifier check 1). `git diff --name-only v0.0.51 HEAD` outside this bundle lists 16 paths: 2 `Localizable.strings`, 7 files under `Sources/UtterPresentation`, 2 under `Sources/UtterPresentationContracts`, 3 tests and `docs/plugin-composition.md` |
| Exactly six tabs, in order | Met | `SettingsTabLayoutTests`. Screenshots `01`, `15`. Over the copy of real data (below), the tab group exposes exactly 6 radio buttons through accessibility |
| No Remote, 遥控器, Plugin Composition or 插件组合 tab | Met | Same tests and screenshots |
| Every Integrations and Plugins control is reachable with unchanged behavior | Met for the controls below | Click-through in the real window: **Developer interface** toggle on shows the clone's own process listening on `127.0.0.1:38765` (`lsof`), toggle off releases the port (`06`). **Add App…** opens an Open panel, Esc closes it. **Register CLI helper** adds "Utter CLI" to the list (`07`). **Delete** removes it. **Reset Token** changes the token (`08`). **Plugins editor Save** writes `plugins.json` and shows "Saved. New sessions will use the updated configuration." (`09`). **Restore default configuration** writes a backup file and shows "Default configuration saved. The previous file was backed up. Restart Utter to apply it." (`10`). Not exercised: adding a real app through the panel, saving an edited or invalid document, the error text path |
| Six labels in full, in zh and en, light and dark | Met | zh dark `01`, en dark `04`, zh light `15`, en light `18`. No ellipsis, overflow control or doubled title row. The window measured 760 x 732 points in total |
| Live language switch, both directions | Met | zh to en: dark `04`, light `18`. en to zh: light `20`. The window title, six tab labels and page text all change in place. General stays selected. The picker exists only on General, so a switch with Integrations selected is not reachable from the UI. The selection lives in `AppState.selectedSettingsID`, which survives the `.id(settings.uiLanguage)` rebuild. A switch with Integrations selected is **not** directly evidenced |
| Missing sections omit cleanly, none means no tab | Met at layout level and for recovery | `testNoMembersMeansNoGroupTab`, the recovery and single-member tests, `testRecoveryLeavesTheIntegrationsTabWithOnlyThePluginsSection`. Real window: `21`. The composition-level case "both members absent" is covered only through the layout function, see verifier finding 3 |
| Unknown or removed selection falls back to a valid tab | Met in tests only | `testUnknownOrRemovedSelectionMapsToNil`, `testSelectionFallsBackToTheFirstTab`. Not exercised in the real window |
| Launch over data written by a newer build does not crash and keeps unrelated settings | Met, two ways | (a) A crafted `plugins.json` naming `presentation.remote`, which v0.0.51 does not know: the app opens Settings in recovery mode with the alert "插件组合无法启动，请在设置的集成页修正配置或恢复默认。" (`22`) and a single 集成 tab holding only the Plugins section (`21`). The file's SHA-256 is identical before and after launch. "Restore default configuration" wrote a backup with the identical SHA-256 (`23`). (b) Launch over **copies** of the owner's current `UserDefaults` domain (it contains `automaticUpdateChecks`, a key that exists only in builds after v0.0.51) and of `dictionary.json`, `edit_rules.json` and `input_history.json`: the process stayed alive for about 50 seconds until it was stopped on purpose, all six tabs were visited, and no new crash report appeared. The model cache directory was not copied. The Activity and Style & Rules pages were visited but their screenshots were not viewed or kept, because they would show the owner's history and dictionary |
| Remote-microphone toggle, status and gain remain in General | Met | `24`: after enabling, "连接状态 未连接" and "音量增益 12 dB" appear. `GeneralSettingsView.swift` has no diff against v0.0.51. The toggle was switched back off |
| Automated tests cover the tab list, merged sections and fallback | Met | `SettingsTabLayoutTests` (11), `SettingsGroupPluginTests` (2, exercising the real `integrations()` and `configuration()` registrations), `BuiltinCatalogTests` (recovery cases) |
| Checks pass, release-style build passes | Partly | See "Automated checks" and Deviation 2 |
| Removed features stated, independent verifier reviewed rollback and rollback of the rollback | Met | "Removed or changed" and "Independent verification" below |

## Removed or changed relative to `main` (accepted by the owner)

Between v0.0.51 and `467e934`: 13 non-merge commits, 241 files, about 15,000 inserted lines.

- The dedicated Remote tab and its diagnostics (device model, discovery method, decoder, reconnect, last capture), connecting an already paired Xiaomi remote, and using the remote microphone for every recording. General keeps the toggle, status and gain from before v0.0.51.
- Sparkle auto-update, appcast signing, the update controls in About and the update-rehearsal tooling. Installs that embed Sparkle (v0.0.52 and later) cannot auto-update to a lower build.
- Developer ID DMG signing and verification, and the related release-artifact workflow and scripts.
- The generation-preparation responsiveness test fix.
- `.tabViewStyle(.grouped)` from `1edb28d`. The intent did not list it. It is gone with the tree and is not needed at six tabs (found by the verifier, finding 2; the approved intent is not edited).
- Persisted data: the only difference is the `automaticUpdateChecks` UserDefaults key. v0.0.51 never reads it. `selectedSettingsID` is not persisted (`AppState.swift`).

## Method of the real-window run

An isolated clone of the release-style app was used so the owner's running Utter
(PID 89532) was never stopped. The clone is a copy of `dist/Utter.app` with
`CFBundleIdentifier` set to `com.opentype.voiceinput.qa`, re-signed ad-hoc with the
original entitlements, and started directly with `CFFIXED_USER_HOME` pointing at a
temporary directory. Windows were captured with `screencapture -l`. Clicks were
posted through System Events at screen coordinates, which moved the pointer briefly.

Isolation evidence:

- `OpenType` was created under the temporary home.
- A SHA-256 baseline of the owner's data directory was taken before the first launch and compared after clone runs. Three comparisons were identical.
- The fourth comparison, after the launch over copies of the owner's data, showed a different `input_history.json`. Its modification time (23:58:29) is 81 seconds before that clone started (23:59:50), no clone was running then, and its newest record carries exactly the same timestamp (`15:58:29Z`, local 23:58:29). The owner's own running Utter appended a record. Test runs are not the cause either: the newest record has that timestamp, and the default history retention is `forever`, so `HistoryStore` does not prune on load.
- The owner's `uiLanguage` stayed `zh`, the owner's `remoteMicEnabled` stayed 0, no `plugins.json` was ever created in the owner's directory, and the QA `UserDefaults` domain and every temporary copy of the owner's data were deleted afterwards.

## Independent verification

Fresh-context, read-only verifier following `docs/sdlc/review-policy.md`, run at `7454531`.
Verdict: **PASS WITH FINDINGS**. No blocker or major finding.

| Check | Verifier result |
|---|---|
| 1. Rollback equality | Pass: tree equality, identical 241-file sets, 16 non-bundle paths all justified by D3 |
| 2. Removed-features accuracy | Pass with one documentation gap (finding 2) |
| 3. Correctness of `21933f2` | Pass: `@MainActor` use, selection normalization, deep link, stale ids, `onAppear` placement, file sizes, strings in both languages |
| 4. Automated checks | Pass: 11 of 11, 2 of 2, 4 of 4, full suite 487 / 18 skipped / 0 failures, both scripts |
| 5. Test quality | Pass with minor gaps (findings 3 and 4) |
| 6. Evidence review | Not usable, see the evidence gap below |
| 7. Rollback path | Pass: revert `21933f2` first, then `7c80d2e`. Reverting `7c80d2e` alone from the current head conflicts on the Settings files |
| 8. Privacy, macOS, release | Pass: no new network or credential surface. Unknown plugin row leads to recovery, not a crash |

Findings and resolutions:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | minor | `NativeDesktopHost.openSettings()` returns early when the window already exists, without normalizing `selectedSettingsID` | Accepted, no change. `SettingsView` normalizes the selection on read, the raw value is not persisted and only the view and host read it |
| 2 | minor | The approved intent does not list the rollback of `.tabViewStyle(.grouped)` | Recorded above. The approved intent is not edited |
| 3 | minor | No composition-level test for "both members absent" | Accepted. `testNoMembersMeansNoGroupTab` covers the rule on the same function with empty input |
| 4 | minor | `testGroupLabelIsLocalizedInBothLanguages` only checked that the strings differ from the key and from each other | **Fixed**: it now asserts exactly "Integrations" and "集成". 11 of 11 pass. This was a test-only change after the verification and the verifier did not re-run it |

Evidence gap: the verifier **could not read the pixel content of the screenshots**.
Its first pass reported viewing some of them, then a retry failed on 12 files, so its
visual claims are not reliable. **The screenshots were reviewed by the implementer
only.** The owner's review at this gate is the only real visual verification.
The launch over copies of the owner's data (b) was added after the verifier ran and
was not independently reviewed.

## Deviations from the plan

1. **Isolation by `HOME` does not work.** The plan said to launch with `HOME` pointing at a temporary directory. A probe showed that Foundation ignores `HOME` on macOS (`FileManager` and `NSHomeDirectory()` still return the real home), so that would have written the owner's real data. `CFFIXED_USER_HOME` was probed and works. A separate bundle id gives a separate `UserDefaults` domain. This is stronger isolation than planned.
2. **Release-style build.** The plan asked for `bash scripts/build-app.sh`. Only `--app-only` was run, which signs locally with an ad-hoc identity. The DMG, the mounted-DMG verification, the checksum and signing with a configured identity were **not** exercised. This is a local QA build, not a release. Per `AGENTS.md`, a release must use the configured identity and must not fall back to ad-hoc signing.
3. **Order of the language switch.** en to zh was captured in light only. zh to en was captured in dark and light.
4. **Appearance.** `-AppleInterfaceStyle Light` did not force light. That attempt's screenshot was discarded. `-NSRequiresAquaSystemAppearance YES` worked.

## Residual risks

- No Developer ID signing, no Sparkle: a release from this branch uses the v0.0.51 pipeline, and Sparkle installs cannot auto-update to it. The version string of any local build comes from the latest git tag (it showed v0.0.57), so a release would need a new SemVer tag above v0.0.57.
- Remote diagnostics are gone. This was accepted at intent approval.
- Plugins editor in recovery mode shows the shipped default document, not the broken text. `reload()` uses `service.document ?? CompositionDocument(bundles: ["desktop"])` and is unchanged from v0.0.51. Whether Save also backs up the previous file was not tested.
- Hotkey, recording, paste and the real remote device were not exercised. The clone inherited the launching terminal's privacy permissions (About showed Accessibility, Microphone and Screen Recording as granted), so Fn could in principle be handled by both apps while it ran. No dictation was triggered.
- The Integrations page headers are bold while General's are small gray text. At v0.0.51 Integrations already used the default `Section(title)` header and General its own `SettingsSectionHeader`, so this is not new.
- The automatic tab style fits six tabs. A seventh top-level tab would bring the overflow back. A new `SettingsGroup` is the cheaper way to add one.
- Pre-existing, not changed here: `Tests/OpenTypeTests/Support/InputHistory.swift` and `PersonalDictionary.swift` point at the real `~/Library/Application Support/OpenType`. A test run can read and rewrite the developer's real history and dictionary. With the default retention `forever` the history store does not prune on load, so no loss was observed.

## Rollback

- Consolidation only: revert `21933f2` (and the later test-only commit). It touches 16 files.
- Whole change: revert `21933f2` first, then `7c80d2e`, or abandon the branch. Reverting `7c80d2e` alone conflicts on the Settings files. The SDLC and evidence commits also have to be reverted or abandoned to match `main` exactly.
- No history was rewritten.
