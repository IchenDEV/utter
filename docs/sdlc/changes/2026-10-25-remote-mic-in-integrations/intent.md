# Intent: Move the Xiaomi remote microphone controls into Integrations

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (intent as written; the five open questions are answered by the spec, which gets its own approval)
**Approved-date:** 2026-10-25
**Upstream:** — (follows `docs/sdlc/changes/2026-10-24-settings-tab-consolidation/`, verification approved 2026-10-25)
**Risk:** Medium. User-visible Settings behavior. No permission, privacy, data format, signing or release change.

## Problem

The owner's original request was to bring the remote control, plugins and
integrations together in one Settings tab. The Settings consolidation that
followed the rollback to v0.0.51 merged only Integrations and Plugins, because
v0.0.51 has no Remote tab. The Xiaomi remote-microphone controls still sit in
General, inside the Audio section next to the Mac microphone picker: a toggle,
a connection status line and a gain slider.

The owner asked whether the Xiaomi microphone is managed in Integrations. Today
it is not, and the owner confirmed they want it there.

## Outcome

In the Integrations tab there is a section for the Xiaomi remote microphone with
the same toggle, connection status and gain slider, behaving exactly as they do
now. General's Audio section no longer shows them. The Settings window keeps six
tabs.

## Scope

In scope:

- moving the remote-microphone toggle, status line and gain slider from General
  to a section in the Integrations tab;
- adjusting user-facing text that points at the old location (see Open
  questions 3), in `en` and `zh-Hans`;
- tests and documentation for the new location.

Out of scope:

- anything about how the remote microphone works: discovery, pairing,
  connection, decoding, gain range, the persisted keys;
- the Remote tab and its diagnostics, which stay removed by the rollback;
- other General or Integrations controls;
- pushing, merging, tagging or releasing.

## Constraints

- The change stacks on the unmerged branch `cursor/settings-tab-consolidation`,
  because it uses that branch's Integrations group. Nothing is pushed or merged
  without a separate owner decision.
- The persisted keys `remoteMicEnabled` and `remoteMicGainDB` stay as they are.
  No migration. A saved profile must show its values in the new place.
- The toggle stays disabled when no remote provider is available, as today.
- Settings pages are contributed by plugins. Disabling a plugin through
  `plugins.json` must not leave an empty block or a broken page. Recovery mode
  must still show an Integrations tab that holds only the Plugins section.
- Every user-facing string goes through `L("key")` with `en` and `zh-Hans`
  entries. Each source file stays under 300 lines. `GeneralSettingsView.swift`
  has 279 lines now.
- The window size and the six-tab order do not change.

## Acceptance criteria

- With the default composition, General shows no remote-microphone toggle,
  status or gain. Its other controls keep their order and behavior.
- With the default composition, the Integrations tab shows one section for the
  Xiaomi remote microphone: a toggle, and when it is on, a connection status
  line and a gain slider from 0 to 24 dB in 1 dB steps. The toggle is disabled
  when no remote provider is available.
- Enabling the toggle and moving the slider in the new place write the same
  settings keys as today. The existing remote-microphone tests pass unchanged.
- A profile saved with `remoteMicEnabled` on and a gain of 18 dB shows both in
  the new place after launch. Nothing else in the profile changes.
- No string in `en` or `zh-Hans` refers to a control "above" or elsewhere that
  no longer exists after the move.
- With the plugin that hosts the section disabled, the Integrations tab omits the
  section cleanly. In recovery mode the Integrations tab holds only Plugins.
- Real-window screenshots in Chinese and English, light and dark, show the new
  section on the Integrations page and General without it, with the tab row still
  six labels in full.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh` and
  `swift test` pass. Automated tests cover the new section's placement and its
  absence from General.
- With a real Xiaomi remote, enabling the toggle in the new place shows the
  connection state. If the owner has no device to test, `verification.md` lists
  this as residual risk.

## Open questions

1. **Where in the Integrations page.** The page now reads: Developer interface,
   Registered apps, HTTP, Plugins. The spec proposes the section between HTTP and
   Plugins, so Plugins stays the last, most technical block. The owner may prefer
   another place.
2. **Move, not copy.** This intent assumes the controls leave General entirely,
   following the owner's "confirm". Say so if you want them in both places.
3. **Text that points at the old place.** The help text says "Keyboard shortcuts
   keep using the Mac microphone selected above". After the move, "above" is the
   Integrations page and the microphone picker is in General. The spec will
   propose new wording for both languages for the owner to review.
4. **How the section is hosted.** As its own member of the Integrations group, so
   it follows the plugin model and is absent in recovery mode, or inside the
   existing Integrations view, which depends on the integration client registry.
   The spec compares both and recommends one.
5. **Branch.** This stacks on the consolidation branch. Whether both land
   together or the consolidation lands first is the owner's decision, after this
   change is verified.
