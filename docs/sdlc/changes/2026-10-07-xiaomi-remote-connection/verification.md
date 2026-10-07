# Verification: Xiaomi Remote 2 Pro connection and settings page

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md` (approved 2026-10-07)

## Evidence

Updated after the review corrections on 2026-10-07, using
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Focused checks used
`swift test --disable-sandbox`; the full suite and signed build ran outside the
agent sandbox with the user's existing test/package authorization.

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/sdlc-checks.sh` | Pass | `SDLC checks passed.` |
| `bash scripts/ci-basic-checks.sh` | Pass | `Basic CI checks passed.` including script harnesses, resource lint, and localization parity |
| Review reproduction before the fixes | Fail as expected | The callback-order, unnamed ATVV, repeated-model, and invalid-model regressions failed on the previous implementation |
| Focused `RemoteMic*` checks | Pass | 92 tests, 0 failures; this sandbox run excluded `RemoteMicPipelineIntegrationTests`, which was covered by the full run below |
| Full `swift test` | Pass | 836 XCTest cases, 18 conditional skips, 0 failures; 1 Swift Testing case also passed. Skips require optional model/download/live-service environments or a bundled test process |
| PCM callback-order reproduction | Pass | Two 240-sample frames match exactly with model-first and capability-first callbacks; premature audio is discarded before initialization. Compiled directly from the production bridge, decoder, and handshake with only pre-roll observation added to the temporary copy |
| `bash scripts/build-app.sh` | Pass | Release app and `dist/Utter-0.0.50.dmg`, Apple Development signed, hardened runtime; signature, resources, DMG checksum, and mounted-app verification passed. Not Apple-notarized |
| Host-session tests | Pass | `RemoteMicHostSessionTests` (6): latch once, join without re-latching, stale stop ignored, own stop ends it, voice key still latches, `MIC_EXTEND` bytes |
| Real remote check | Not run | Requires the physical remote |

Logs from this run: `/private/tmp/utter-fix-{before,remote-tests,full-tests,
sdlc,ci-basic,pcm,build}.log`. The DMG SHA-256 is
`8b4be9ab9f1ebad41b381610f069b6a576e4a643ba26576f8b645c99be02ebc0`.

Earlier sandbox-only full-suite runs aborted in unrelated CoreAudio/AppKit
paths. The normal-environment full-suite pass above supersedes that limitation.

## Acceptance criteria

- Connected-in-macOS remote found without scanning — `testRemoteAlreadyConnectedInSystemSettingsIsConnectedWithoutScanning`, `testRemoteConnectedAsHIDKeyboardIsFoundByName`.
- Missing/renamed ATVV name does not prevent connection — `testConnectedVoiceServiceDoesNotRequireAnApprovedName`; HID-only devices retain the exact-name filter.
- Unrelated devices ignored, unfiltered scan used — `testUnrelatedConnectedDevicesFallBackToAnUnfilteredScan`, `testOtherNamesAreRejected`.
- `ARN9` nibble order per attempt; stale read ignored — `testModelNumberSelectsTheNibbleOrderForTheCurrentAttempt`, `testModelNumberFromASupersededAttemptIsIgnored`, `testLowNibbleFirstDecodesTheSwappedByteLikeTheStandardOrder`.
- Model and capabilities must both complete before recording — `testRecordingWaitsForModelAndCapabilitiesInEitherCallbackOrder`, `testInvalidModelDoesNotAllowRecording`, `testMissingOptionalModelUsesTheLegacyDecoder`, `testModelCannotChangeDecoderOrderAfterInitialization`, and the handshake reconnect/reset checks.
- Candidate filtering — `testAdvertisingTheVoiceServiceMakesAnyNameACandidate`.
- Remote tab text keys exist in both localizations, General no longer holds the controls — `testSettingsTextKeysAreLocalized`, key-parity check.
- Real-window light/dark screenshots and interaction checks — pending. Opening the exact rebuilt app path through native computer automation returned `Computer Use server error -10005: timeoutReached`; retrying by bundle ID reported three copies and required an exact path. The app was absent from the subsequent running-app inventory. No successful launch, screenshot, or interaction is claimed.

## Final interface audit

Read all 1,599 lines of `/Users/chenli/.codex/ANTI_SLOP.md` before the copy
change and again before delivery; audited every rule for applicability.

- Truthful, specific copy: both languages now describe temporary recording
  storage and local/cloud recognition. The false memory-only/no-upload promise
  is removed. Model-read failure has an actionable localized error.
- Visible content and hierarchy: the help remains native `Section` footer text
  inside the grouped `Form`, with no entrance animation, opacity gate, or new
  clipping/line limit. It is shown when the remote feature is enabled.
- Controls and accessibility: the existing native toggle, slider, buttons, and
  status text remain bound to settings/bridge actions. A status dot is accompanied
  by readable text. Actual pointer/keyboard operation remains unverified because
  the app-open attempt above timed out.
- Typography, spacing, contrast, and appearance: native typography and semantic
  colors remain in use; no decorative type, gradient, glow, border, or motion was
  introduced. The longer footer and new error need real-window checks for wrapping,
  clipping, and contrast in both appearances. These are not marked passed.
- Website-only composition rules (heroes, CTAs, pricing, testimonials, logo
  walls, illustrations, footers, custom backgrounds, font-library choices) do
  not apply to this native settings-copy correction.

## Residual risk

- Not verified on real hardware: whether this unit reports `ARN9`, and whether
  macOS returns it from `retrieveConnectedPeripherals`. The Remote tab shows the
  model, discovery route, and last recording source so a tester can report them.
- Missing optional Device Information keeps the legacy high-nibble-first order;
  an ARN9 unit that omits its model entirely cannot be positively identified by
  the model read. An advertised but unreadable model fails instead of guessing.
- Unverified on hardware: whether the remote streams after a host `MIC_OPEN`
  with no key press, how long it streams before its own timeout, and whether
  `MIC_EXTEND` is honoured. The 3 s silence fallback bounds the failure, and
  the tab's "Last recording" shows which microphone was used.
- The silence fallback with the lid closed ends in the existing no-usable-input
  error, since no other microphone exists.
- `XiaomiRemoteMicBridge.swift` remains far above the 300-line guideline; this
  change adds ~100 lines there and does not split it.
- The licensing question for the earlier remote-mic work is still open.

## Decision

Ready for review pending CI and a real-device pass.
