# Spec: Roll back to v0.0.51 and consolidate Settings tabs

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (design D1 to D3 as written, with D2 as recommended: a pure v0.0.51 tree, no Developer ID cherry-pick)
**Approved-date:** 2026-10-24
**Upstream:** intent.md (approved 2026-10-24)
**Risk:** High, the rollback range includes release, signing and packaging files

## Context

### Evidence for the title-bar problem

| Release | Settings tabs | Tab style |
|---|---|---|
| v0.0.50 | 6 | automatic |
| v0.0.51 | 7 (adds Plugins) | automatic |
| v0.0.52 to v0.0.55 | 8 (adds Remote) | automatic |
| v0.0.56 and later | 8 | `.grouped` (`1edb28d`) |

- `docs/sdlc/changes/2026-10-17-auto-update/evidence/part-b-ui-audit.md` records
  that "automatic styling hid all navigation behind toolbar overflow" at eight
  tabs and that `.grouped` was the fix. That is the repository's own evidence
  that the eight-tab count, not the title bar code, is the root cause.
- Six-tab automatic rendering is visible in the untracked screenshots
  `artifacts/screenshots/utter-settings-*-v2.png` in the owner's checkout.
- No real-window render of v0.0.51 plus this change exists yet. It is produced
  at verification and is the acceptance evidence, not this paragraph.

### How Settings is assembled at v0.0.51

- Each Settings page is a `PresentationContribution` registered by a plugin
  through `PresentationPlugins.contribution(...)`. The catalog sorts them by
  `(order, id)`. `SettingsView` renders one `TabView` tab per contribution.
- Orders: history 0, general 10, models 20, style 30, integrations 40, about 50,
  plugins (`presentation.configuration`) 60.
- `NativeDesktopHost.openSettings` checks `AppState.selectedSettingsID` against
  the contribution ids and falls back to the first one. The Models recovery
  action sets that id to `presentation.models`.
- `BuiltinCompositions.recoveryIDs` contains `presentation.configuration` but
  not `presentation.integrations`. When the saved composition fails to resolve,
  only recovery plugins mount, `AppDelegate` shows the `plugins.recovery` alert,
  and the Plugins page is the user's only way to fix or reset the document.
  The merged tab therefore must not depend on the Integrations plugin.
- `docs/plugin-composition.md` states that saving rejects unknown plugin ids.
  `CompositionResolver.resolve` validates every row and bundle, so
  `CompositionStore.load` throws on a `plugins.json` that names one unknown to
  v0.0.51. `BuiltinApplication.start` then mounts only the recovery plugins and
  records `compositionFailure`. The app enters recovery instead of crashing.
- v0.0.51 keeps basic remote-microphone support: General has the toggle, status
  and gain slider, and `SettingsStore` already persists `remoteMicEnabled` and
  `remoteMicGainDB`.
- Between v0.0.51 and `origin/main`, the only persisted-data change is the
  `automaticUpdateChecks` UserDefaults key. Older code never reads it, and
  `UserDefaults` tolerates unread keys.

## Design

### D1. History-preserving rollback

On branch `cursor/settings-tab-consolidation`, based on `origin/main` (`467e934`):

1. Commit 1, "Restore the product tree to v0.0.51". Produced mechanically with
   `git read-tree --reset -u v0.0.51` and a commit. No authored content. The
   SDLC bundle is still untracked at this point, so it is not removed.
2. Commit 2, the SDLC bundle (documents only).
3. Commit 3, the Settings consolidation: code, strings, tests, docs.

Nothing is pushed, merged or tagged. `main`, its history and the v0.0.52 to
v0.0.57 tags are untouched.

Checks that make commit 1 reviewable without trust:
`git diff --quiet v0.0.51 <commit 1>` succeeds, and `git diff --stat <commit 1>~1
<commit 1>` shows the same 241 files that differ between v0.0.51 and `main`.

### D2. Release and signing files (answers open question 2)

Recommendation: restore them with everything else, so the tree is exactly
v0.0.51 before commit 3.

- The approved intent chose a whole-product rollback.
- Sparkle changed `Package.swift`, `Package.resolved`, `Info.plist`,
  `build-app.sh`, `release-artifact.yml` and `verify-release-artifact.sh`, the
  same files as the Developer ID work. A mix would produce a tree that was never
  built or tested in that state.
- Consequence: Developer ID DMG signing and verification (`8d1134c`) and the
  generation-preparation test fix (`8dc9547`) are absent. Releases from this
  branch use the v0.0.51 pipeline. This is a stated residual risk.

Alternative, not applied: restore to v0.0.51, then cherry-pick `8d1134c` and
`8dc9547`. `git merge-tree` shows both apply cleanly on v0.0.51, and neither
touches Remote or Sparkle. This deviates from the approved acceptance criterion
that only the Settings change differs from v0.0.51, so it needs an intent
amendment and a fresh approval. It is offered only if the owner wants Developer
ID signing kept.

The lane stays High. This branch is never released as part of this change.

### D3. Grouped Settings tabs

Plugin ownership, section ids and the recovery bundle stay as they are. Only the
way tabs are built changes.

- `PresentationContribution` gains `group: String? = nil`.
  `PresentationPlugins.contribution(...)` gains a matching `group:` parameter.
  Both are `package` API inside the same package.
- A small pure descriptor `SettingsGroup`, with one value:
  `integrations` has id `presentation.group.integrations`, label key
  `settings.integrations`, symbol `point.3.connected.trianglepath.dotted` and
  order 40.
- Members: `presentation.integrations` (group `integrations`, order 0 in the
  group) and `presentation.configuration` (group `integrations`, order 10).
  Their ids, `requires` and recovery membership do not change.
- A new pure type `SettingsTabLayout` in `UtterPresentation`:
  - `tabs(from: [PresentationContribution]) -> [SettingsTab]`. An ungrouped
    contribution is its own tab. Contributions sharing a known group id become
    one tab, shown only if at least one member is registered. Members with an
    unknown group id become individual tabs so nothing is hidden. Tabs are
    sorted by `(order, id)`.
  - `tabID(for selection: String, in tabs: [SettingsTab]) -> String?` maps a
    member id such as `presentation.configuration` to its group tab id, returns
    the id itself for a plain tab, and returns `nil` for an unknown id.
- `SettingsView` iterates the tabs. A plain tab renders its contribution as
  today. A group tab renders `SettingsGroupPage`, a single
  `Form { ForEach(members) { $0.view(context) } }` with `.formStyle(.grouped)`,
  `.scrollContentBackground(.hidden)` and `.settingsPageSurface()`, the same
  modifiers the member pages apply now. One `Form` means one scroll area.
- `IntegrationsSettingsView` and `PluginConfigurationView` stop wrapping their
  content in a `Form` and stop applying those modifiers. They return their
  `Section`s. Each keeps its own `onAppear` hook on its own content.
- `NativeDesktopHost.openSettings` validates and normalizes
  `selectedSettingsID` with `SettingsTabLayout.tabID(for:in:)`.
- `SettingsView` keeps no `tabViewStyle` modifier, so the automatic style from
  v0.0.51 stays (answers open question 3). The `.id(settings.uiLanguage)`
  refresh stays as it is at v0.0.51.
- Strings: `plugins.recovery` changes in `en` and `zh-Hans` to name the
  Integrations page. English: "The plugin combination could not start. Open
  Integrations in Settings to correct it or restore defaults." Chinese:
  "插件组合无法启动，请在设置的集成页修正配置或恢复默认。" The section header
  `plugins.title` stays.
- `docs/plugin-composition.md` changes "设置 → 插件" to "设置 → 集成".

Resulting default tabs: Activity (0), General (10), Models (20), Style & Rules
(30), Integrations (40), About (50).

## Failure analysis

| Failure | Effect | Handling and evidence |
|---|---|---|
| Saved `plugins.json` from v0.0.57 names a row unknown at v0.0.51 | Composition fails, recovery bundle mounts, alert shown | The Integrations tab shows only the Plugins section, so the user can reset. Unit test with only the configuration member; manual launch with a crafted file |
| Integrations plugin disabled by the user | Tab has one section | Same unit test shape, other member |
| Both members absent | No tab | Unit test: no tab with id `presentation.group.integrations` |
| `Section`s wrapped in `AnyView` lose grouped styling inside one `Form` | Cards look flat or misaligned | Real-window check in light and dark. If it fails, stop and return to the owner before touching the `AnyView` contract |
| Six Chinese or English labels clip at 760 points, including after a live language switch | The original title-bar symptom returns | Check both directions in the real window. If it fails, stop. Do not bring back `.grouped` without owner approval |
| `selectedSettingsID` holds a member id or a removed id | Wrong or blank tab | `tabID(for:in:)` maps members and falls back to the first tab. Unit tests |
| Downgraded user keeps v0.0.57 defaults | Unread keys remain | No migration needed. Manual launch over a v0.0.57 defaults domain |
| Sparkle-embedded v0.0.57 installs | Cannot auto-update to a lower build | Out of scope. No release is cut here |
| Developer ID DMG signing absent from this branch | A release here would use the older pipeline | Residual risk in D2. Never fall back to ad-hoc signing. Label self-signed output as not Apple-notarized |

## Rollback

- Whole change: abandon the branch, or revert commit 1 to get `main`'s tree back.
- Consolidation only: revert commit 3. Commit 2 holds documents only.
- No force-push and no history rewrite happens at any point.

## Verification approach

- Unit tests `SettingsTabLayoutTests`: default tab list and order, merged
  members in order, recovery layout with only the configuration member, only the
  integrations member, neither, unknown group id, member-id mapping, unknown-id
  fallback, and a localization-key check for the group label.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`
  and a release-style build with `bash scripts/build-app.sh`.
- Real-window screenshots of every tab label row in Chinese and English, light
  and dark, plus a live language switch in both directions. Stored under this
  change's `evidence/` directory.
- Manual runs: recovery launch with a bad `plugins.json`, launch over v0.0.57
  defaults, and a click through every control in the merged tab.
- High-risk lane: an independent verifier, with no part in the implementation,
  checks D1 equality, the consolidation diff and the rollback path, following
  `docs/sdlc/review-policy.md`. The result is recorded in `verification.md`.

## Clarifications to the intent

- At v0.0.51 the English label of the Plugins page is "Plugins". Intent
  criteria that say "Plugin Composition" mean this page under either label.
- The intent's equality criterion applies to the tree after commit 1. After
  commits 2 and 3, `git diff v0.0.51` lists only this change's documents,
  Settings code, strings and tests.
