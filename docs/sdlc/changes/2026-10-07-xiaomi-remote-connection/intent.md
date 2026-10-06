# Intent: Make the Xiaomi Remote 2 Pro microphone actually connect, and give it a settings page

**Status:** approved
**Approved-by:** User (conversation: "完成调研后开始实现，无需审批")
**Approved-date:** 2026-10-07
**Upstream:** User report in this conversation, 2026-10-07; follow-up to `2026-09-21-remote-mic-integration`

## Problem

With the Xiaomi Bluetooth Remote 2 Pro paired, Utter still records from the
Mac's own microphone. Research (code audit plus the reference project
`IchenDEV/remote-mic-app`) found why the remote is never used:

1. Utter only *scans* for the ATVV voice service. A remote that is already
   connected in System Settings → Bluetooth stops advertising, so the scan never
   reports it and the bridge sits at "searching" forever. No ATVV `AUDIO_START`
   ever arrives, so no voice-key session is latched and every recording falls
   through to the system microphone. The reference app first asks CoreBluetooth
   for connections macOS already holds.
2. The scan is filtered by the service UUID, so a remote that advertises only
   its name is missed. The reference app scans unfiltered and matches known
   names.
3. The Remote 2 / 2 Pro (model `ARN9`) packs ADPCM low-nibble-first. Utter always
   decodes high-nibble-first, which would turn a connected remote's speech into
   noise.
4. The only UI is a toggle inside General. There is no way to see why the remote
   is not being used, to reconnect, or to tell which microphone a recording used.

## Outcome

- A remote that is already connected in macOS is found and used without waiting
  for an advertisement; a remote that only advertises its name is also found.
- The remote's model is read and the correct ADPCM nibble order is used.
- A dedicated "Remote" settings tab shows connection state, model, how the remote
  was found, the decoding mode, a reconnect action, a Bluetooth settings shortcut,
  gain, and which microphone the last recording used.

## Scope

Affected: `Sources/RemoteMic/` (discovery, model read, diagnostics),
`AudioCaptureManager` (records the capture source), the settings UI (new tab; the
controls move out of General), localizations, and tests.

Non-goals: new permissions or entitlements, key remapping or HID capture, using
the remote's microphone for keyboard-shortcut recordings, battery display, and
any change to the ATVV session or release logic.

## Constraints

- Default off; only enabling the feature may trigger Bluetooth access.
- No new dependency; CoreBluetooth only; no new entitlement or Info.plist key.
- Matching stays exact-name based so other vendors' ATVV remotes are never
  adopted by name alone.
- Audio stays in memory; no upload.
- The existing session-token and fallback-to-system-mic behavior is unchanged.

## Acceptance criteria

- A remote returned by `retrieveConnectedPeripherals` for the voice service, or
  for the HID service with an approved name, is connected without scanning.
- Unrelated connected devices are ignored and the bridge falls back to an
  unfiltered scan.
- A model number containing `ARN9` switches the decoder to low-nibble-first for
  that attempt only; a late model read from a superseded attempt is ignored.
- Discovered peripherals are filtered by voice service or approved name.
- The Remote tab renders the diagnostics and every key it uses exists in both
  localizations; General no longer contains the remote controls.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and
  `swift test` pass.

## Open questions

- Hardware: whether this particular unit reports `ARN9`, and whether macOS hands
  back the remote from `retrieveConnectedPeripherals`, can only be confirmed on
  the real device. The settings page exposes both so the tester can report them.
- Licensing for the earlier remote-mic work is unchanged and still open in
  `2026-09-21-remote-mic-integration`.
