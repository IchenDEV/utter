# Intent: Roll back to v0.0.51 and consolidate Settings tabs

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (after choosing a whole-product rollback to v0.0.51, the merged tab name Integrations and a stacked layout)
**Approved-date:** 2026-10-24
**Upstream:** —             # link to the previous stage artifact
**Risk:** High while the rollback range includes release, signing and
packaging files (see Scope). The spec may narrow the range and lower the lane.

**Approval note.** The owner approved this intent with open question 2 still
unanswered, so the spec must propose an answer and the owner reviews it at spec
approval. After approval, one factual correction was applied: v0.0.51 still has
basic remote-microphone support in General, so the rollback removes less than
the first draft stated. The Scope and open question 1 below carry the corrected
text.

## Problem

The Settings window now has eight top-level tabs: Activity, General, Models,
Style & Rules, Remote, Integrations, About and Plugin Composition. The owner
reports the Settings title bar is broken. In the reported screenshot the window
shows a title row, a second row holding a pill of eight tabs, and an extra
control at the top right.

Tab history, from the repository:

| Release | Date | Settings tabs | Tab style |
|---|---|---|---|
| v0.0.50 | 2026-10-04 | 6 | automatic |
| v0.0.51 | 2026-10-08 | 7 (adds Plugin Composition) | automatic |
| v0.0.52 to v0.0.55 | 2026-10-11 to 10-16 | 8 (adds Remote) | automatic |
| v0.0.56 and later | 2026-10-21 | 8 | `.grouped` (`1edb28d`) |

Suspected cause, not yet confirmed: with eight tabs the automatic style
overflowed into the toolbar, and `1edb28d` forced `.tabViewStyle(.grouped)` to
show them. The spec must confirm this by rendering the real window.

## Outcome

The product code returns to the state of v0.0.51 (`3c69c8d`, 2026-10-08), as a
new history-preserving change on a new branch. On top of it, Settings has six
tabs in this order: Activity, General, Models, Style & Rules, Integrations,
About. The Integrations tab holds the existing Integrations content and the
Plugin Composition editor, stacked on one scrolling page. The title bar and tab
strip render as a single standard area in Chinese and English, in light and dark
appearance.

## Owner decisions

Recorded from the owner's answers on 2026-10-24:

- Roll back the whole product to v0.0.51, not only the tab style.
- The merged tab is named Integrations (集成).
- Its sections are stacked on one page, not switched with a segmented control.

## Scope

In scope:

- restoring the tree to v0.0.51 with revert-style commits on a new branch, so
  `main`, its history and the published v0.0.52 to v0.0.57 tags are untouched;
- one merged Integrations tab holding Integrations and Plugin Composition;
- tests and documentation for the six-tab structure.

Removed by the rollback, accepted by the owner (13 non-merge commits, 241 files,
about 15,000 inserted lines since v0.0.51):

- the dedicated Remote tab and its diagnostics (device model, discovery method,
  decoder, reconnect, last capture), connecting an already-paired Xiaomi
  remote, and using the remote microphone for every recording (`34e7738`,
  `86c7bcc`, `3b063ec`, and the merge `0dc31b9`). Remote-microphone support
  from before v0.0.51 stays: General keeps its toggle, status and gain slider;
- Sparkle auto-update, appcast signing, the update controls in About and the
  update-rehearsal tooling (`077f6d8`, `d994b9b`, `ba12e66`, `ca7356c`,
  `1edb28d`);
- Developer ID DMG signing and verification, and the related release-artifact
  workflow and scripts (`8d1134c`);
- the generation-preparation responsiveness test fix (`8dc9547`).

Out of scope:

- pushing, merging, tagging, releasing or deleting any branch or tag;
- changes to the behavior of Activity, General, Models, Style & Rules, About,
  Integrations or Plugin Composition beyond relocating the last two.

## Constraints

- Nothing is pushed or merged without a separate owner decision. The rollback
  lives only on the local branch `cursor/settings-tab-consolidation`.
- No history rewrite and no force-push. The rollback must be undoable by
  reverting its commits.
- Settings pages are contributed by plugins. Disabling a plugin through
  `plugins.json` must still remove its section without leaving an empty block,
  and the Integrations tab must not appear if none of its sections is available.
- `AppState.selectedSettingsID` deep links, such as the Models recovery action,
  must keep landing on the right tab.
- The window stays fixed at 760 by 680 points and non-resizable.
- Every user-facing string goes through `L("key")` with `en` and `zh-Hans`
  entries. Each source file stays under 300 lines.
- A release built from this branch must keep passing the signing and checksum
  checks that exist at v0.0.51. It must never fall back to ad-hoc signing, and
  it must be labeled as not Apple-notarized if it is self-signed.
- A user who already installed v0.0.52 or later and has remote-mic settings
  saved must not crash on launch after the rollback. Unknown saved keys are
  ignored.

## Acceptance criteria

- The tree outside the Settings change equals v0.0.51: a diff against
  `v0.0.51` lists only the Settings consolidation, its tests and its SDLC
  documents.
- With the default composition, the Settings window has exactly six tabs in the
  order Activity, General, Models, Style & Rules, Integrations, About.
- No top-level tab is titled Remote, 遥控器, Plugin Composition or 插件组合.
- Every control reachable today from the Integrations and Plugin Composition
  tabs is reachable from the merged tab with unchanged behavior.
- A real-window screenshot in Chinese and English, light and dark, shows all six
  tab labels in full with no ellipsis, overflow control or doubled title row.
- When the integration registry or the configuration service is unavailable, the
  merged tab omits that section instead of showing an empty one. With neither
  available, the tab is not shown.
- Opening Settings with a section id that no longer exists falls back to a valid
  tab.
- Launching the rolled-back build over a settings store written by v0.0.57 does
  not crash and does not discard unrelated settings.
- Automated tests cover the tab list, the merged-tab section selection and the
  fallback. `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`
  and `swift test` pass. A release-style build passes because packaging files
  are in the rollback range.
- `verification.md` states the removed features and that an independent
  verifier reviewed the rollback and the rollback-of-the-rollback path.

## Open questions

1. Resolved by the owner's approval. The owner asked to merge "遥控器" into one
   tab and also chose v0.0.51, which has no Remote tab. This intent follows the
   explicit v0.0.51 choice, so the Remote tab's diagnostics disappear instead of
   being merged. Only the basic toggle, status and gain remain, in General.
2. Open, answered in the spec. Should the release and signing files (`.github/workflows/release-artifact.yml`,
   `scripts/build-app.sh`, `scripts/verify-release-artifact.sh`) also be rolled
   back, or stay at their current state so releases keep Developer ID checks?
   Keeping them lowers the risk lane but requires `Package.swift` and
   `Package.resolved` to stay consistent with the older sources.
3. Open, answered in the spec. Whether the tab style stays automatic depends on
   the real-window render at six tabs. The spec records the evidence.
