# Spec: Cut the Settings window to six tabs without rolling back any feature

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (design D1 to D7 as written, including the answers to intent questions 1 to 3: automatic tab style, the Remote section header, and leaving PR #131 untouched in this change)
**Approved-date:** 2026-10-25
**Upstream:** intent.md (approved 2026-10-25)
**Risk:** Medium. User-visible Settings layout and navigation. No permission, privacy, data format, signing or release change.

## Context

Facts about `origin/main` (`467e934`) that the design relies on:

- Eight Settings pages, each a `PresentationContribution` with role `.settings`,
  sorted by `(order, id)`: history 0, general 10, models 20, style 30,
  `presentation.remote` 35, `presentation.integrations` 40, about 50,
  `presentation.configuration` 60 (label `plugins.title`, shown as "Plugins").
- `SettingsView` is one `TabView` with a tab per page and
  `.tabViewStyle(.grouped)`. The 2026-10-17 audit says `.grouped` was added because
  the automatic style hid navigation in toolbar overflow at eight tabs.
- Today each of the three pages to merge owns a full `Form` with
  `.formStyle(.grouped)` and `.settingsPageSurface()`:
  `IntegrationsSettingsView` (104 lines), `RemoteMicSettingsView` (127 lines, reads
  `PlatformProjection` as an environment object) and `PluginConfigurationView`.
- Remote's first section (the switch, with the usage note as its footer) has no
  header. Its other sections are headed Connection and Audio and appear only while
  the switch is on.
- `NativeDesktopHost.openSettings()` accepts `state.selectedSettingsID` only if it
  equals a page id, else falls back to the first page. `installSettingsContent`
  rebuilds the hosting view on a language change. `selectedSettingsID` is not
  persisted. The only other writer is the model-recovery deep link
  (`presentation.models`).
- `BuiltinCompositions.recoveryIDs` lists the pages that survive a failed
  composition. It includes `presentation.configuration` and not
  `presentation.integrations` or `presentation.remote`.
- The same grouping design was built and verified on the withdrawn rollback branch
  (`cursor/settings-tab-consolidation`, commit `21933f2`): a `group` field,
  `SettingsGroup`, `SettingsTabLayout` and `SettingsGroupPage`, with the automatic
  tab style. Those files do not depend on anything the rollback removed, so the
  design is re-applied on `main`; no other part of that branch is used.

## Design

### D1. Pages can name a group

`PresentationContribution` gets `group: String? = nil` and
`PresentationPlugins.contribution(...)` gets a matching `group:` parameter, both
defaulting to nil, so every other page and every external caller is unchanged.

New `SettingsGroup` in `UtterPresentationContracts`: one group,
`SettingsGroup.integrations`, with id `presentation.group.integrations`, label
`settings.integrations`, symbol `point.3.connected.trianglepath.dotted`, order 40.
Its label and symbol are exactly what the Integrations tab has today.

### D2. Tab layout

New `SettingsTabLayout` (pure, `@MainActor`, about 47 lines) turns the page list
into tabs:

- A page whose `group` names a known group joins that group's tab. Every other page
  is its own tab, as today. An unknown group id is treated as no group.
- A group tab exists only if it has at least one member. Members sort by
  `(order, id)`. Tabs sort by `(order, id)`.
- `tabID(for:in:)` maps a selection to the tab that shows it: a tab id or a member
  page id. `selection(_:in:)` adds the fallback to the first tab for an unknown id.

New `SettingsGroupPage` (about 19 lines) is one scrolling grouped `Form` that
renders each member's view in order, with `.formStyle(.grouped)`,
`.scrollContentBackground(.hidden)` and `.settingsPageSurface()` applied once.

`SettingsView` builds its tabs from the layout. A single-page tab renders the page
as now; a group tab renders `SettingsGroupPage`. The tab selection binding reads
and writes tab ids and normalizes a member id to its tab.
`NativeDesktopHost.openSettings()` replaces its `contains` check with
`SettingsTabLayout.selection`. `installSettingsContent` is unchanged.

### D3. The three pages become bare sections (answers intent question 2)

| Plugin id | Order in group | Registration change | View change |
|---|---|---|---|
| `presentation.integrations` | 0 | `group:`, order 40 to 0 | Drop the outer `Form`, `.formStyle`, `.settingsPageSurface()`. Sections unchanged |
| `presentation.remote` | 5 | `group:`, order 35 to 5; passes the projection as `RemoteMicSettingsView(platform:)` | Drop the outer `Form`, `.formStyle`, `.scrollContentBackground`, `.settingsPageSurface()`. `platform` becomes an `@ObservedObject` parameter, so no environment wrapper sits between the group form and its sections. The `settings.remoteMicEnabled` branch, rows, labels, ranges and diagnostics stay as they are |
| `presentation.configuration` | 10 | `group:`, order 60 to 10 | Drop the outer `Form` and modifiers; `reload()` runs from the description row's `onAppear` |

Result, top to bottom: Developer interface, Registered apps, HTTP, then Remote
(switch and usage note; when on: Connection, Audio), then Plugins. The tab label
stays "Integrations" / "集成".

One addition: Remote's first section, which has no header today, gets
`Section(L("tab.remote")) { ... } footer: { ... }`. With the page no longer a tab of
its own, a headerless block would sit between HTTP and Plugins with nothing to say
what it is. `tab.remote` ("Remote" / "遥控器") exists in both languages, so no new
string. Every other header, row and footer keeps its text. Say so if you want the
block left headerless.

Plugin ids, `recoveryIDs` and the `desktop` bundle contents do not change. Each file
stays under 300 lines (Remote and Integrations get a few lines shorter).

### D4. Tab style (answers intent question 1)

Remove `.tabViewStyle(.grouped)` from `SettingsView`, returning to the automatic
style of v0.0.50 and v0.0.51. The earlier rounds verified that six labels fit at 760
points in zh and en, light and dark, and after a live language switch. That was on
another base, so this build is checked again in real windows (see Test strategy).
If any label clips or moves into overflow, the change stops and returns to the owner;
`.grouped` is not kept silently.

### D5. Recovery, disabling and selection (acceptance criteria 4 and 5)

- A page that is disabled or fails to start is simply absent, so its section is
  absent. The other members stay. With no members there is no Integrations tab.
- Recovery mounts only `presentation.configuration`, so the Integrations tab holds
  only Plugins. `plugins.recovery` now says "Open Integrations in Settings...", so
  the text matches the tab that holds the Plugins section.
- `selectedSettingsID` equal to `presentation.remote`, `presentation.configuration` or
  `presentation.integrations` resolves to the Integrations tab. An unknown id
  resolves to the first tab. A deep link to Remote lands on the top of the
  Integrations tab; there is no scroll-to-section.
- An existing `plugins.json` that is valid on `main` is parsed exactly as before;
  no id, bundle or binding changes.

### D6. Strings and docs

| Item | Change |
|---|---|
| `plugins.recovery` en | "The plugin combination could not start. Open Integrations in Settings to correct it or restore defaults." (the existing sentence with the tab name replaced) |
| `plugins.recovery` zh-Hans | "插件组合无法启动，请在设置的集成页修正配置或恢复默认。" (was "...设置的插件组合页...") |
| `docs/plugin-composition.md` line 7 | "在“设置 → 插件”编辑并保存 JSON" to "在“设置 → 集成”的“插件组合”分区编辑并保存 JSON" |

No key is added or removed, so `en` and `zh-Hans` parity is unaffected. `plugins.title`
("Plugins" / "插件组合") stays as the section header.

### D7. Branch and landing (answers intent question 3)

All work stays on `cursor/settings-menu-only`, one commit per SDLC stage and one for
code. Draft PR #131 and `cursor/settings-tab-consolidation` are not touched in this
change. Closing the PR is a GitHub action on shared state, so I will ask you
separately once this change has results, and will not do it unprompted. Pushing,
opening a PR for this branch, merging, tagging and replacing your installed Utter are
also separate decisions.

### Files

New: `Sources/UtterPresentationContracts/SettingsGroup.swift`,
`Sources/UtterPresentation/SettingsTabLayout.swift`,
`Sources/UtterPresentation/UI/SettingsGroupPage.swift`,
`Tests/OpenTypeTests/SettingsTabLayoutTests.swift`,
`Tests/OpenTypeTests/SettingsGroupPluginTests.swift`.

Edited: `PresentationServices.swift` (contract), `PresentationPlugins.swift`,
`PresentationPlugins+Settings.swift`, `PresentationPlugins+Configuration.swift`,
`UI/IntegrationsSettingsView.swift`, `UI/RemoteMicSettingsView.swift`,
`UI/SettingsView.swift`, `NativeDesktopHost+Windows.swift`, both
`Localizable.strings`, `docs/plugin-composition.md`, and the SDLC bundle.

The diff against `origin/main` must stay inside that list. It must not touch
`Package.swift`, `Package.resolved`, `scripts/`, `.github/`,
`Resources/Info.plist`, or the update, signing, audio or remote-capture modules.

### Non-goals

Any rollback. Remote-microphone discovery, pairing, decoding, gain and diagnostics.
Integration, HTTP and plugin-configuration behavior. The other five tabs. A
scroll-to-section deep link. Persisted settings, a migration, or a new plugin id.

## Safety and failure modes

No new permission, entitlement, network call, file or persisted key.

| Failure | Effect | Handling and evidence |
|---|---|---|
| Three pages in one grouped `Form` render flat, misaligned, or lose their state | Page looks or behaves broken | Real-window check, light and zh/en, with the remote switch off and on. The Remote branch is copied, not rewritten; its `@ObservedObject` projection keeps updating the status rows. Stop and return to you if wrong |
| The Plugins editor inside a long scrolling form fails to load its text or loses focus | Cannot edit plugins | Real-window check of the editor and Save and Reset visible. `reload()` still runs on first appear |
| Six labels clip, or the automatic style overflows | The reported bug stays | Real windows in zh and en, light and dark, and after a live language switch in both directions. Stop condition, see D4 |
| Dark mode cannot be forced on the isolated clone (known from earlier rounds) | Missing dark real-window evidence | Best-effort alternative below. If it is not faithful, the gap is recorded and I ask you before changing system appearance |
| A page disabled in `plugins.json` | Its section disappears; stored settings still apply | Unit tests for every one-missing and two-missing combination; real-window check with `presentation.remote` disabled |
| Recovery mode | Integrations tab holds only Plugins | Unit test on the layout of the recovery set; existing recovery tests run unchanged. Real-window check with a deliberately broken `plugins.json` in the isolated clone |
| Selection by a removed or unknown id | Empty or wrong tab | `SettingsTabLayoutTests` (member id, tab id, unknown id, empty list) |
| Habit: people look for a Remote tab | It is now a section | Accepted at intent approval |
| Your running Utter or data is touched | Data loss risk | Isolated clone as in earlier rounds; hashes of the data files and defaults taken before and after; only the clone's own PID is stopped |

## Test strategy

Tests are written first and seen to fail where they can (the layout tests fail to
compile until `SettingsTabLayout` exists).

| Acceptance criterion | Check |
|---|---|
| Six tabs, in order, with the default composition | `SettingsTabLayoutTests`: the eight page descriptors as on `main` give tabs `history, general, models, style, group.integrations, about` and the group's members are `integrations, remote, configuration`. Real-window screenshots |
| Every section present and unchanged | Real-window screenshots of the Integrations tab top and scrolled, in zh and en, with the remote switch off and on (seeded isolated defaults domain). Comparison list of section headers and rows against `main`'s three pages. Existing `RemoteMicPluginTests`, `RemoteSessionIngressTests`, `RemoteMicGainSettingsTests`, `SettingsProjectionTests` and `SettingsStoreTests` pass without edits |
| Diff scope | `git diff --name-only origin/main` is listed in `verification.md` and checked against the allow list above |
| Disabling pages; recovery | `SettingsGroupPluginTests` mounts the real registrations with fixtures and expects the tab members for each combination, and only Plugins for the recovery set. Existing `BuiltinCatalogTests` recovery tests run unchanged |
| `plugins.json` and selection | Layout tests for member id, tab id, unknown id. Existing composition-loading tests run unchanged. Real-window check with `presentation.remote` disabled in the clone's `plugins.json` |
| Text and docs name Integrations | Unit test: in `en` and `zh-Hans`, `plugins.recovery` contains the localized `settings.integrations`. `rg` over docs and strings, recorded in `verification.md`, finds no remaining pointer to a Plugins or Remote tab |
| Labels in full, zh and en, light and dark, live language switch | Isolated clone as in the earlier rounds (copy of `dist/Utter.app` built with `bash scripts/build-app.sh --app-only`, distinct bundle id, ad-hoc re-sign, `CFFIXED_USER_HOME`). Light, zh and en, real windows; live switch in both directions through the General language picker. Dark: the system is in light mode and a process cannot be forced dark from outside, so I will try an in-process alternative: host the real `SettingsView` in a titled `NSWindow` with `appearance = .darkAqua` and capture that window. It is used only if the same harness in `.aqua` matches the real light capture. Otherwise the dark gap is recorded and you are asked |
| Repository checks | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`, and a release-style `bash scripts/build-app.sh --app-only` |
| Real Xiaomi remote | Not available to the agent. Left to you after landing and recorded as residual risk. This change does not alter remote behavior |

Known hazard carried from earlier rounds: `swift test` rewrites two JSON files in
the OpenType data directory with identical content and leaves
`OpenTypeServiceTests-*.plist` files in `~/Library/Preferences`. File hashes and a
`defaults export` hash are taken before the first test run and compared after.

## Rollout and rollback

- Nothing ships from this change. No tag, push, release, or install.
- Rollback: `git revert` the code commit. The eight tabs and `.tabViewStyle(.grouped)`
  return. No persisted key changed, so no data needs repair.
- Stop conditions: a section renders wrongly in the grouped form, a label clips in
  any real window, an existing test needs an edit to pass, the diff leaves the
  allow list, or your running Utter or data is touched.
