# Verification: Xiaomi Remote 2 Pro connection and settings page

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md` (approved 2026-10-07)

## Continuation: 2026-10-10

This section supersedes the earlier local OCR failure and app-only artifact
status. Production and test sources remain at
`0dc31b90d279a9688bc303a44604a1176e8b5a8b`; this update records verification
without changing implementation or adding a test exclusion.

| Check | Result | Evidence |
|---|---|---|
| GitHub PR CI | Pass | [Run 38049101239](https://github.com/IchenDEV/utter/actions/runs/38049101239): Contract & Tests, Release-style App Build, and SDLC Gate all succeeded on `0dc31b9`. GitHub reports `MERGEABLE` and `CLEAN` |
| GitHub complete Swift suite | Pass | 1,143 XCTest cases, 18 conditional skips, 0 failures; 1 Swift Testing case passes. The previously failing synthetic Chinese/English OCR test passes |
| Local complete Swift suite | Pass | Same 1,143 XCTest cases, 18 conditional skips, 0 failures, plus 1 Swift Testing case. No test excluded; synthetic OCR passes |
| Local repository guardrails | Pass | `sdlc-checks.sh` and `ci-basic-checks.sh` rerun successfully, including module boundaries, resource ownership, script regressions, localization parity, and conflict-marker checks |
| Current signed test package | Pass | Full `build-app.sh` generates the current app and DMG. Apple Development signing, hardened runtime, owned resources, DMG checksum, mounted signature, and byte-for-byte mounted-app comparison pass. Not Apple-notarized |
| Settings and physical remote | Not verified | The UI attempt below does not establish settings interactions or appearances. No real remote capture was run |

Local tests used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
and `swift test --build-system native --disable-index-store
-debug-info-format none -j 4`. Packaging used the same developer directory and
`SIGN_IDENTITY='Apple Development' bash scripts/build-app.sh`.
The OCR pass followed recovery of disk capacity; no root cause for the earlier
Vision failure is asserted.

- Current package: `dist/Utter-0.0.50.dmg`, built from `0dc31b9`.
- SHA-256: `2158ddaf575ebca4574f5d2615bf906dd29a6f3ba0f74bd213ea0d4f96903450`.
- Previous package preserved as `dist/archive/Utter-0.0.50-3b063ecc.dmg`, with
  its original SHA-256 `8b4be9ab9f1ebad41b381610f069b6a576e4a643ba26576f8b645c99be02ebc0`.
- Logs: `/private/tmp/utter-pr122-continuation-tests.log`,
  `/private/tmp/utter-pr122-continuation-package.log`, and
  `/private/tmp/utter-pr122-ci-success.log`; local guardrail logs are
  `/private/tmp/utter-pr122-continuation-{sdlc,ci}.log`.

### Interface audit during continuation

Read and reread all 1,599 lines of `/Users/chenli/.codex/ANTI_SLOP.md` and
checked every point for applicability. No interface source changed during this
continuation. The source audit below remains applicable, including native
controls, visible content, semantic typography/colors, truthful localized
copy, and the absence of new decorative motion or containers. Marketing-page
composition and bespoke display-art rules do not apply to this native settings
verification.

The exact rebuilt app launched as QA PID 58104. Accessibility exposed its menu
bar but returned no windows after status-item activation. CoreGraphics found
its popover window, and a window-only capture was inspected at
`.build/pr122-qa/menu.png`. It shows the menu content, not the Remote settings
page. A later coordinate click reached another window after the transient
popover disappeared; no settings action was confirmed. The coordinate route
was stopped. The QA process was terminated and its absence confirmed before
packaging. No settings value or system appearance was intentionally changed.
Toggle, slider, reconnect, keyboard navigation, wrapping, contrast, and
light/dark acceptance remain pending; the menu capture does not satisfy them.

## Main integration: 2026-10-10

Merged `main` at `64817558dc1e50911a198e0025bee6d6cafdea6d` into
`t3/xiaomi-remote-mic` using the repository's merge-commit convention. The
feature now follows main's plugin modules rather than restoring deleted
monolithic files:

- `UtterRemoteMic` retains main's scoped transports, callback identities, task
  draining, frozen stream gain, and file cleanup. It adds connected-device
  discovery, model-gated ARN9 decoding, host sessions, and `MIC_EXTEND`.
- `UtterAudio` receives the remote preference through the session's immutable
  capture request. Shortcut/menu/API capture can open the remote microphone and
  fall back after 3 seconds of silence. Closing capture cancels and drains its
  silence task.
- The Remote tab is a `UtterPresentation` contribution. Its state, diagnostics,
  and reconnect action use contracts and `PlatformProjection`; the view imports
  no provider implementation. General retains main's login/device services.
- Main's capture-before-model-preparation behavior and numeral/list processing
  remain intact. New regressions cover host capture ownership, shutdown callback
  rejection, settings diagnostics disposal, and remote preference propagation
  while the model resource lease is held.

| Check | Result | Evidence |
|---|---|---|
| SDLC and basic CI | Pass | Both required scripts pass, including module boundaries, owned resources, localization parity, and harness tests |
| Complete Swift suite | One failure | 1,142 XCTest cases, 17 conditional skips, 1 failure; the additional Swift Testing case passes |
| OCR failure recheck | Fail | `ScreenReliabilityTests.testAccurateOCRReadsSyntheticChineseAndEnglishMailInOrder` reports Vision `e5rtError` in the full run and `unknownError` alone. Both the test and OCR production source are unchanged from main; no baseline main run is claimed |
| Remaining full suite | Pass | Explicitly excluding only that OCR test: 1,141 XCTest cases, 17 conditional skips, 0 failures; 1 Swift Testing case passes |
| Final remote/model-queue regressions | Pass | 97 cases, including the added settings projection observation/disposal test, 0 failures |
| Release app | Pass | `SIGN_IDENTITY='Apple Development' bash scripts/build-app.sh --app-only`; Metal/resource bundles, hardened-runtime signature, and release artifact verification pass. Not Apple-notarized |
| Native app launch | Pass | Exact rebuilt `dist/Utter.app` launched as a separate process; that QA process exited afterward and the installed `/Applications/Utter.app` process was preserved |
| Real settings interactions and appearances | Not verified | Accessibility automation could inspect and invoke the rebuilt app's menus, but no settings window was returned. No toggle, slider, reconnect, light/dark screenshot, contrast, or wrapping pass is claimed |
| Physical remote | Not run | Requires the real device |

Commands used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
Swift tests used `--build-system native --disable-index-store
-debug-info-format none -j 4`. The default Swift build engine initially failed
while signing a test bundle; the first native attempt exhausted disk space.
Only this run's generated `.build/out` cache was removed before retrying.
No signing failure was bypassed in the release app build.

Current logs: `/private/tmp/utter-main-merge-{ci,tests-native,ocr-retry,
remote-final,build}.log` and `.build/merge-tests-excluding-ocr.log`.
The rebuilt artifact is `dist/Utter.app`; the DMG listed below is the older
2026-10-07 artifact and was not regenerated for this merge.

### Interface audit after the merge

Reread all 1,599 lines of `/Users/chenli/.codex/ANTI_SLOP.md` before handoff
and checked each rule for applicability to this native settings migration.

- Visibility and hierarchy: native grouped Form sections and localized footer
  text remain visible without animation gates. No new fixed content height,
  clipping, overlays, or ornamental containers were added.
- Controls: native toggle/slider bindings write through the settings service;
  reconnect calls the scoped control service. The toggle is disabled when the
  remote provider is absent. Automated tests prove diagnostics propagation and
  disposal, not pointer/keyboard interaction.
- Typography and color: system typography, semantic surfaces, and secondary
  text remain in use. Monospaced digits are limited to the dB value. The status
  dot has accompanying readable state text. Real-window contrast, spacing,
  clipping, and appearance checks remain pending.
- Specific and truthful copy: both languages retain the actual discovery,
  decoding, fallback, temporary-file, and local/cloud processing descriptions.
  Localization lint and key parity pass.
- Cohesion and decoration: the tab reuses main's settings contribution and
  surface system. No gradient, glow, custom shadow, novelty font, entrance
  reveal, fake product UI, or hover motion was introduced. Website-only rules
  about heroes, pricing, logos, illustrations, and footers do not apply here.

## 2026-10-07 review evidence

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
- The original oversized bridge is now split across main's native module
  extensions; all remote-mic source files are below the 300-line guideline.
- The licensing question for the earlier remote-mic work is still open.

## Decision

Ready for review with passing CI and the complete local test suite.
Real-device and settings-window acceptance remain pending.
