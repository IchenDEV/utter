# Verification: Xiaomi remote wireless microphone in Utter

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Bundle hash and restoration | Pass | Bundle SHA-256 `021ed0088aaf8db0df1f7d6afc452d7c9115b7a00e65bb87cffcfd6d5b8b2651`; `git bundle verify`, `git fsck --full --strict`, ref `6bdcbb78c4f7091f1225b93ca82306560c9683d7`, tree `0addbb55d3ba9ff0dc7791afec3c012c19b53c42`, and clean restore all passed. |
| Host and toolchain | Pass | Mac mini `Mac16,10` / Apple M4 / macOS 27.2; Xcode 27.0 (`27A266a`), Swift 6.4 from `/Applications/Xcode.app/Contents/Developer`. |
| `bash scripts/ci-basic-checks.sh` | Pass | Exit 0 with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and `SDKROOT=.../MacOSX27.0.sdk`; all static, localization, vocabulary, resource, and secret checks passed. |
| `bash scripts/sdlc-checks.sh` | Pass | Exit 0: "SDLC checks passed." |
| `swift test --filter RemoteMic` | Pass | Exit 0; 72 tests, 0 failures, including persisted 0 dB gain, 30-second pre-roll capacity, and ATVV v1.0 stream-id parsing/close encoding. |
| `swift test --filter RemoteMicCallbackRoutingTests` | Pass | Exit 0; 7 tests, 0 failures. |
| `review-evidence/vec4-central-gate-mutations.sh` | Pass | Exit 0; baseline 7 tests passed; manager, peripheral, and attempt mutations each exited 1 with the target assertion classified; every restore returned exact head/tree and clean status. |
| `swift test` (full suite) | Pass | Exit 0; 705 tests executed, 10 environment/model-gated tests skipped, 0 failures. |
| `bash scripts/build-app.sh --app-only` | Pass | Exit 0; Release arm64 app and CLI helper built, ad-hoc hardened-runtime signed, `verify-release-artifact.sh` reported valid on disk and designated requirement satisfied; app binary SHA-256 `68eb91f0ff30ccfada4c2854208aaf56e9c472effb30945888e6c56141a351ca`. |
| Real Xiaomi remote end-to-end | Not run | No hardware in this environment |

Environment note: the current evidence was collected on the online Mac mini
above using the full Xcode toolchain. The first CI-basic invocation without an
explicit SDK failed at the industry vocabulary check because the host target
was `arm64-apple-macosx27.2.0` while the selected Xcode SDK was 27.0; the
explicit `SDKROOT` rerun passed and is the recorded result. The earlier Linux
bundle verification remains historical evidence only.

### 2026-09-22 Mac mini rerun details

The PR review fixes were rerun locally on the exact PR head plus this working
tree. They preserve system-input selection for keyboard/API sessions, retain up
to 30 seconds of decoded pre-roll, echo the ATVV v1.0 stream id in `MIC_CLOSE`,
and distinguish a persisted 0 dB gain from an absent preference. Both check
scripts, the 72-test RemoteMic slice, the 705-test full suite, and the
release-style app build passed. Hardware and licensing gates remain open.

The bundle's checked-in mutation script initially had three trailing shell
continuations that swallowed the following `run_mutation` calls. The minimal
script repair is commit `58473722ddee842c01218c2fe2ffb8a9cd1ed7f3`; the
preceding compile repair is commit `f8b135b3cf4498c447f5dd447424b36e82818e01`.
The final tree is commit `58473722ddee842c01218c2fe2ffb8a9cd1ed7f3`, tree
`b00cdb9b2e57930a26731496507df70033c1def4`, and the final mutation script
SHA-256 is
`52dcad02bc0fbcea2ced082705b0764c004fa73642f0f59c2500b07879da170c`.
The complete logs are attached to the VEC-4 handoff comment.

### VEC-4 / #104 lifecycle evidence

The following tests are the acceptance boundary for the incremental central
lifecycle patch. They enter through `activate()` and the injectable central
transport factory, retain the transport-owned delegate proxy, and route every
event through the same production bridge methods. The fake supplies non-nil
manager/peripheral identities; it does not call a proxy-only helper. The
identity tests vary exactly one source field at a time, and the retirement
tests use weak boxes plus a fake transport `deinit` counter rather than a
strong transport array. Every injected factory captures the bridge weakly, so
the fixture cannot keep its subject alive through the bridge → factory → bridge
cycle. The connection-retirement test asserts transport release and exactly one
`deinit` immediately after the terminal callback, before creating or driving
the replacement connection.

| Counterexample | Intended result | Mac mini result |
|---|---|---|
| `testProductionCentralRetirementCancelsPendingAndDefersFastReactivation` | `cancel` is issued for a still-connecting peripheral; off→on does not create a second transport until the old proxy's terminal failure; old contexts release, then late same-peripheral connect/fail/disconnect events are ignored | **Passed** — focused suite and mutation harness on Xcode 27 |
| `testScanRetirementUsesNonBlockingFenceBeforeReactivation` | scan-only retirement is retained behind the production `DispatchQueue.main.async` fence; the test awaits a subsequent main-queue turn, then checks replacement creation and weak/deinit release | **Passed** — focused suite and mutation harness on Xcode 27 |
| `testCentralManagerIdentityGateRejectsWrongManager` | same attempt/peripheral plus wrong manager is ignored | **Passed** — baseline and manager mutation assertion both recorded |
| `testCentralPeripheralIdentityGateRejectsWrongPeripheral` | same manager/attempt plus wrong peripheral is ignored | **Passed** — baseline and peripheral mutation assertion both recorded |
| `testCentralAttemptIdentityGateRejectsWrongAttempt` | same manager/peripheral plus stale attempt is ignored | **Passed** — baseline and attempt mutation assertion both recorded |

`review-evidence/vec4-central-gate-mutations.sh` runs the unmutated focused
suite, then removes only the manager, peripheral, or paired source-attempt
comparisons in a temporary checkout. Each mutation is accepted only when its
exact target test and unique assertion marker both appear in the XCTest failure
record. A zero exit, compile/link/fatal failure, signal, timeout, or unrelated
test failure is rejected. The default per-run timeout is 1,800 seconds for a
cold first build. The unified log preserves environment versions, commands,
complete stdout/stderr, mutation diffs, original test exit codes, elapsed
times, and the exact clean HEAD/tree/status proof after every restoration.

The harness classifier's `--self-test` is runnable without Swift and verifies
that simulated compile, signal, timeout, and unrelated-test failures are
rejected. That classifier self-test is not an XCTest result. On the Mac mini,
the baseline and all three real mutation XCTest runs completed with the real
exit codes described above.

The production guarantee is backed by the focused Mac mini XCTest and mutation
evidence; it remains bounded by the unperformed hardware pass below.

### Changes after the independent review of the first head

The review of the initial implementation raised four code blockers; the
licensing question is a human/CTO item and is untouched here.

| Finding | Status | What changed |
|---|---|---|
| P0: voice key not wired to Utter's hotkey | Fixed | The remote's `AUDIO_START` (0x04) on the ATVV control channel latches the session and drives `AppDelegate.startRecording`; `AUDIO_STOP` (0x00) and disconnect stop it. `0x08` is `START_SEARCH`, not a microphone-open request, per the AOSP ATVV reference firmware. No HID F5→Fn remap or Input Monitoring permission is needed. |
| P0: short press / cold start recorded after release | Fixed | `RemoteMicSession` latches press → starting → recording; a release or disconnect before the commit cancels the pending start (`RemoteMicSessionTests`, `RemoteMicSessionOrderingTests`). |
| P0: first audio lost / stop could not close | Fixed | Early audio is held in `RemoteMicPreRoll` and drained on commit; `STREAM_STOP` releases before clearing state so `endCapture` closes the microphone exactly once (`RemoteMicPreRollTests`). |
| P1: handshake generation isolation missing | Fixed | `RemoteMicHandshake.confirmCapabilities` now requires the request to have been sent, so a late capability frame on a reused peripheral cannot mark a new attempt ready; `didUpdateValueFor` checks peripheral identity (`RemoteMicHandshakeTests`). |
| P1: closing the feature left a session recording | Fixed | `deactivate()` invalidates the session and fires released/stopped, and `applyRemoteMicSetting(false)` cancels the session before deactivating. |
| P0: cancellation did not reach the real VoicePipeline start | Fixed | `startRecording` now returns the task that owns the whole `pipeline.start`; the remote path stores and cancels it, and passes the latch into `pipeline.start`, which re-checks it after the model wait via `RemoteMicStartGuard`. A released or cancelled start aborts and never falls back to the system mic. |
| P1: same-peripheral attempt isolation missing | Fixed in this increment | Each lifecycle is created through `activate()` and a new central transport/delegate proxy. Central routes require the non-nil manager identity, non-nil peripheral identity, captured attempt, and lifecycle phase. A pending or connected peripheral is always passed to `cancelPeripheralConnection`; the old central/peripheral contexts remain retained until `didFailToConnect`/`didDisconnectPeripheral`. Scan-only retirement uses a main-queue fence. `RemoteMicCallbackRoutingTests` drives the production factory/proxy route, asserts non-nil identities, exercises pending-cancel failure completion, fast off→on, context release, and late same-peripheral `didConnect`/`didDisconnect`. |
| P0: normal release discarded the recording | Fixed | `RemoteMicReleaseDecision.applyRelease` drives the production release path: a committed recording is stopped (its WAV is needed), only an uncommitted start is cancelled (`RemoteMicReleasePathTests`). |
| P0: disabling the feature left the pipeline recording | Fixed | `RemoteMicShutdownDecision` stops the pipeline when a recording is active, because the bridge's release callback is suppressed once the setting is off. |
| P1: cold-model counterexample only tested a helper | Fixed | `RemoteMicPipelineIntegrationTests` drives the real `VoicePipeline.start` await through an injected model-load barrier and a capture spy, proving a released/superseded start never reaches recording or capture. |
| P1: idle audio polluted the next pre-roll | Fixed | `RemoteMicAudioRouting` (used by the bridge) drops audio with no live session; buffered only while starting (`RemoteMicAudioRoutingTests`). |
| P0: fallback leaked wanted state | Fixed | `RemoteMicWantedState` holds the want; a failed start calls `tearDownFailedStart()`, clearing the callback, ending capture, and dropping the temp file, so a later readiness cannot open the remote mic mid-system-session. Covered by `RemoteMicWantedStateTests`. |
| P1: handshake had no state gates | Fixed | `RemoteMicHandshake` requests capabilities only after both notifications are confirmed via `didUpdateNotificationStateFor`, once per attempt; connection and initialization timeouts (`connectionTimeout` 10 s, `initializationTimeout` 8 s) bound each attempt; `didFailToConnect` recovers; a monotonic `generation` rejects late callbacks. Covered by `RemoteMicHandshakeTests`. |
| P1: only pure protocol tests | Addressed in part | The gate and wanted-state are pure, injectable types with deterministic tests; the Mac mini run exercised the real bridge factory/proxy route. The CoreBluetooth transport still needs a real device. |

## Acceptance criteria

- Setting off keeps the existing path — pass by construction
  (`AudioCaptureManager.start` only consults the remote when
  `remoteMicEnabled`); covered by the full Mac mini suite.
- A remote voice-key session uses the decoded stream — implemented, but **not
  verified**: requires the physical remote.
- Keyboard-shortcut and developer-API sessions continue using the selected
  system input, including while the remote feature is enabled.
- Voice key starts and stops recording — implemented through the control-channel
  adoption path; **not verified on hardware**.
- Handshake ordering, attempt isolation, and timeouts are covered by
  deterministic tests (`RemoteMicHandshakeTests`,
  `RemoteMicAttemptIsolationTests`); the RemoteMic Mac mini run passed all 72
  tests.
- Source-bound same-peripheral late-event regression — specified in
  `swift test --filter RemoteMicCallbackRoutingTests`; the test uses the
  `activate()`/transport-factory production creation path, validates non-nil
  manager/peripheral identities, holds the attempt-1 transport/proxy through
  terminal cancellation, then delivers old disconnect/control/didConnect/
  didFail events through that proxy. The Mac mini run passed all seven focused
  tests, and the three mutation counterexamples each produced the intended
  failing assertion before exact restoration.
- Session cancel across the real pipeline path — `RemoteMicPipelineIntegrationTests`
  passed in the RemoteMic run, including the real `VoicePipeline.start` await
  barrier and capture spy. Hardware timing remains unverified.
- Localization parity and SDLC checks — pass; `ci-basic-checks.sh` and
  `sdlc-checks.sh` both passed with the explicit Xcode SDK.

## Residual risk

- **No hardware verification.** Pairing, scan/connect, the two notification
  subscriptions, the voice key press/release, first and last frame, session
  teardown on disconnect, reconnect, and real 16 kHz audio all still need a
  person with the remote. This is the largest gap.
- The 10 skipped tests are **all** environment/model-dependent — this tree has
  no `OPENTYPE_LIVE_DOWNLOAD_INTEGRATION` gate at all. The skip names are:
  `ANELMRuntimeTests.testRealGenerationLifecycleWhenModelIsProvided`,
  `AppleSpeechAnalyzerIntegrationTests.testTranscribesBundledChineseSample`,
  `ChatTemplateProbe.testRenderQwen35Template`,
  `DeferredReplacementPolicyTests.testDecisionRequiresSameFrontmostApp`,
  `EspressoFallbackTests.testRealANEFailureFallsBackToInstalledMLX`,
  `PromptDumpProbe.testDumpPrompts`,
  `QwenNativeASREngineTests.testExistingModelNativeBenchmark`,
  `QwenNativeASREngineTests.testExistingModelTranscribesRepositorySamplesWithoutDownloadingWeights`,
  `StreamingASRIntegrationTests.testVolcStreamingSessionEmitsPartialCallbackFromSampleAudio`,
  `StreamingASRIntegrationTests.testWhisperStreamingSessionEmitsPartialCallbackFromSampleAudio`.
  An earlier revision of this file wrongly attributed 4 of them to a
  live-download gate borrowed from the #102 tree.
- **Licensing is pending human determination.** `IchenDEV/remote-mic-app` is
  GPL-3.0-only while Utter is MIT. This development verification makes no
  finding that the implementation is independent, derivative, adequately
  attributed, or distributable. A human licensing owner must record the
  provenance, attribution, and distribution decision before any release; the
  setting stays default off.
- The bridge assumes CoreBluetooth callbacks on the main queue and main-thread
  callers, matching the existing capture style.
- **CoreBluetooth callback boundary.** Apple’s API gives central delegate
  methods a `CBPeripheral`, but no connection-attempt id; the bridge therefore
  creates one central manager/delegate proxy per lifecycle and captures the
  attempt when discovery starts `connect`. A pending or connected peripheral is
  explicitly cancelled on retirement, and the manager/peripheral/proxy context
  is released only after the old manager's terminal `didFailToConnect` or
  `didDisconnectPeripheral`; a scan-only manager uses an explicit `.main`
  queue fence because it has no peripheral terminal callback. Late callbacks
  from a retained old manager reach the old proxy and fail the source-attempt,
  manager-identity, peripheral-identity, and lifecycle-phase gates; the
  regression does not infer isolation from the replacement object’s mutable
  state. The guarantee is bounded by CoreBluetooth delivering callbacks through
  the manager’s `.main` queue and by all connection changes entering this proxy
  route. A direct unbound `CBCentralManagerDelegate` call is rejected for
  connection events; hardware validation must confirm the actual
  manager/proxy lifecycle.
- `AudioCaptureActivity` thresholds were tuned for the built-in mic; the remote
  path uses the same gate with a user-adjustable gain.

### Handover steps for the hardware pass

1. Build and run: `bash scripts/build-and-run.sh --verify`.
2. Pair the remote in System Settings → Bluetooth.
3. Settings → General → enable "Xiaomi remote wireless mic"; confirm the state
   line reaches connected.
4. Hold the remote's voice key and speak; confirm Utter records and inserts text.
5. Release the key; confirm recording stops.
6. Disconnect the remote mid-session; confirm the session ends cleanly and the
   state returns to scanning/retrying.
7. Reconnect; confirm a new session works.
8. Capture the app log and, if possible, a screenshot of the settings state.

## Decision

Development verification passed. Release remains blocked on independent
hardware verification and the pending human licensing decision. Do not enable
or distribute the feature until both are resolved; human approval is recorded
separately.
