# Intent: Cut the Settings window to six tabs without rolling back any feature

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (intent as written; the three open questions are answered by the spec, which gets its own approval; draft PR #131 is not touched by this approval)
**Approved-date:** 2026-10-25
**Upstream:** — (supersedes the "whole-product rollback" decision of `docs/sdlc/changes/2026-10-24-settings-tab-consolidation/`, which the owner withdrew on 2026-10-25: "功能不回退，只改菜单")
**Risk:** Medium. User-visible Settings layout and navigation. No permission, privacy, data format, signing or release change.

## Problem

The Settings window on `main` has eight tabs: Activity, General, Models, Style &
Rules, Remote, Integrations, About and Plugins. The owner reports that the title bar
looks broken. The repository's own audit
(`docs/sdlc/changes/2026-10-17-auto-update/evidence/part-b-ui-audit.md`) records the
cause as the tab count: at eight tabs the automatic style hid navigation behind
toolbar overflow, and `.tabViewStyle(.grouped)` was added as the workaround. The
owner asked for fewer tabs, with Remote, Plugins and Integrations in one tab.

An earlier round answered that by rolling the whole product back to v0.0.51 and
merging only Plugins and Integrations, because v0.0.51 has no Remote tab. That
removed features: the Remote tab and its diagnostics, Sparkle auto-update and
Developer ID signing. The owner did not want that. Only the menu should change.

## Outcome

On top of the current `main`, the Settings window has six tabs: Activity, General,
Models, Style & Rules, Integrations, About. The Integrations tab is one scrolling
page that holds everything the Integrations, Remote and Plugins tabs hold today.
No feature is removed or changed.

## Scope

In scope:

- grouping the three existing Settings pages into one tab, and the tab layout code,
  labels, strings, tests and documentation that need it;
- the tab style of the Settings window, if the six-tab layout needs a different one
  (open question 1).

Out of scope:

- any rollback of code: Sparkle, Developer ID signing, the Remote capture and
  diagnostics code, packaging, scripts and workflows stay as on `main`;
- how the remote microphone, integrations or plugin configuration work;
- the other tabs, and any persisted setting or data;
- pushing, merging, tagging or releasing.

## Constraints

- Based on `origin/main` (`467e934`), in its own branch and worktree. The earlier
  branch `cursor/settings-tab-consolidation` and draft PR #131 are not built on.
  Its tab-grouping idea may be re-applied; its rollback is not.
- Plugin ids do not change, including `presentation.remote`,
  `presentation.integrations` and `presentation.configuration`. Disabling a plugin
  through `plugins.json` must keep working. Recovery mode (`recoveryIDs`) must still
  show a Plugins page when the composition cannot start.
- Persisted keys do not change. No migration.
- Every user-facing string goes through `L("key")` with `en` and `zh-Hans` entries.
  Each source file stays under 300 lines.
- Real-window QA must not touch the owner's running Utter or data (isolated clone,
  as in the earlier rounds).

## Acceptance criteria

- With the default composition the Settings window has exactly six tabs, in this
  order: Activity, General, Models, Style & Rules, Integrations, About. There is no
  Remote and no Plugins tab.
- Every section that the Integrations, Remote and Plugins pages show on `main`
  appears in the Integrations tab, in the order Integrations, Remote, Plugins, and
  works as before. This includes the remote-microphone switch with its usage note,
  and, when the switch is on, the connection and audio sections and the
  diagnostics rows.
- `git diff origin/main` touches only Settings tab layout code, localized strings,
  tests and documentation. It touches nothing in `Package.swift`, `Package.resolved`,
  `scripts/`, `.github/`, `Resources/Info.plist`, or the update, signing, audio or
  remote-capture modules.
- Disabling any one of the three plugins leaves the other sections in the tab. With
  all three absent there is no Integrations tab. In recovery mode the Integrations
  tab holds only Plugins.
- An existing `plugins.json` that is valid on `main` still loads, and a selection
  naming `presentation.remote` or `presentation.configuration` opens the Integrations
  tab. An unknown selection opens the first tab.
- Text and documentation that send the user to the Plugins tab now name Integrations.
- In real windows, in Chinese and English, light and dark, and after a live language
  switch in both directions, all six tab labels show in full.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh` and `swift test`
  pass, with tests for the tab layout, the member order and the recovery layout.
- The owner can confirm the Remote section against a real Xiaomi remote. If not, it
  is listed as residual risk. The change does not alter remote behavior.

## Open questions

1. **Tab style.** `main` forces `.tabViewStyle(.grouped)` on the Settings tab view
   (added to cope with eight tabs). The earlier rounds showed that the automatic
   style, the look of v0.0.50 and v0.0.51, fits six tabs at 760 points in both
   languages. Recommendation: return to the automatic style, and confirm it in real
   windows on this build. Say so if you want `.grouped` kept.
2. **Order and names inside the tab.** Recommended order: Integrations, Remote,
   Plugins. The tab label stays "Integrations" / "集成". The section headers keep
   the names they have today.
3. **The earlier work.** Draft PR #131 and the branch
   `cursor/settings-tab-consolidation` describe the rollback you did not want.
   Recommendation: close the PR and keep the branch only as a record. The
   "remote mic into Integrations" change is not needed here, because `main` already
   keeps those controls in the Remote page that this change merges.
