# Verification: Xiaomi remote wireless microphone in Utter

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." (localization parity, plists, resources) |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `swift build` | Pass | `Build complete!` with the Command Line Tools toolchain |
| `swift test` (full suite) | Pass | 696 executed, 10 skipped, 0 failures |
| `swift test --filter RemoteMic` | Pass | 63 tests, 0 failures |
| Real Xiaomi remote end-to-end | Not run | No hardware in this environment |

Test command note: this machine has no downloadable Metal toolchain, so the
Xcode build backend cannot compile `mlx-swift`'s Metal sources; the suite ran
with the Xcode toolchain and `--build-system native`.

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
| P1: same-peripheral attempt isolation missing | Fixed in this increment | Each connection lifecycle installs a source-bound `XiaomiRemoteMicPeripheralDelegateProxy`; every peripheral callback carries the proxy's captured attempt through the production route. Central callbacks have no source id in CoreBluetooth and are limited to the current object plus disconnected/connected state boundary. `RemoteMicCallbackRoutingTests` retains the old proxy and delivers late disconnect/control events through the production route. |
| P0: normal release discarded the recording | Fixed | `RemoteMicReleaseDecision.applyRelease` drives the production release path: a committed recording is stopped (its WAV is needed), only an uncommitted start is cancelled (`RemoteMicReleasePathTests`). |
| P0: disabling the feature left the pipeline recording | Fixed | `RemoteMicShutdownDecision` stops the pipeline when a recording is active, because the bridge's release callback is suppressed once the setting is off. |
| P1: cold-model counterexample only tested a helper | Fixed | `RemoteMicPipelineIntegrationTests` drives the real `VoicePipeline.start` await through an injected model-load barrier and a capture spy, proving a released/superseded start never reaches recording or capture. |
| P1: idle audio polluted the next pre-roll | Fixed | `RemoteMicAudioRouting` (used by the bridge) drops audio with no live session; buffered only while starting (`RemoteMicAudioRoutingTests`). |
| P0: fallback leaked wanted state | Fixed | `RemoteMicWantedState` holds the want; a failed start calls `tearDownFailedStart()`, clearing the callback, ending capture, and dropping the temp file, so a later readiness cannot open the remote mic mid-system-session. Covered by `RemoteMicWantedStateTests`. |
| P1: handshake had no state gates | Fixed | `RemoteMicHandshake` requests capabilities only after both notifications are confirmed via `didUpdateNotificationStateFor`, once per attempt; connection and initialization timeouts (`connectionTimeout` 10 s, `initializationTimeout` 8 s) bound each attempt; `didFailToConnect` recovers; a monotonic `generation` rejects late callbacks. Covered by `RemoteMicHandshakeTests`. |
| P1: only pure protocol tests | Addressed in part | The gate and wanted-state are now pure, injectable types with deterministic tests (20 total). The CoreBluetooth transport itself still needs a real device. |

## Acceptance criteria

- Setting off keeps the existing path — pass by construction
  (`AudioCaptureManager.start` only consults the remote when
  `remoteMicEnabled`); the full suite passes.
- Setting on with a connected remote uses the decoded stream — implemented, but
  **not verified**: requires the physical remote.
- Setting on with no remote falls back to the system input — pass by
  construction (`RemoteMicCaptureManager.start` returns false unless the bridge
  is `.ready`), and the failure path now provably leaves no residue.
- Voice key starts and stops recording — implemented through the control-channel
  adoption path; **not verified on hardware**.
- Handshake ordering, attempt isolation, and timeouts covered by deterministic tests — pass (`RemoteMicHandshakeTests`, `RemoteMicAttemptIsolationTests`).
- Source-bound same-peripheral late-event regression — run
  `swift test --filter RemoteMicCallbackRoutingTests`; the test retains the
  attempt-1 production delegate proxy, starts attempt 2 on the same simulated
  object, and delivers disconnect/control through that proxy. A mutation that
  replaces the proxy's captured attempt with the live attempt must fail this
  test.
- Session cancel across the real pipeline path — pass at the unit boundary: `RemoteMicStartGuardTests` mirrors the pipeline's post-model check and fails 3 cases under the old behaviour (mutation check). The live `VoicePipeline.start` await itself still needs a hardware/timing run.
- Localization parity and check scripts — pass.

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
- **Licensing.** `IchenDEV/remote-mic-app` is GPL-3.0-only and the reviewer found
  the protocol implementation structurally close to it. A human must resolve
  attribution/licensing before any distribution; the setting stays default off.
- The bridge assumes CoreBluetooth callbacks on the main queue and main-thread
  callers, matching the existing capture style.
- **CoreBluetooth callback boundary.** `CBPeripheralDelegate` callbacks are
  source-bound by a lifecycle proxy, so a queued service/characteristic/
  notification/value event from an old lifecycle cannot use the replacement's
  handshake. `CBCentralManagerDelegate` callbacks do not carry an attempt id;
  the bridge accepts them only for the current peripheral and compatible
  connected/disconnected state. This protects a late failure/disconnect after
  a replacement is connected, but cannot identify two simultaneous central
  events for the same object beyond CoreBluetooth's serialized main delegate
  queue; reconnects must remain serialized through this lifecycle.
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

Blocked on independent hardware verification and the licensing decision. Do not
enable the setting for users until both are resolved. Human approval is recorded
separately.
