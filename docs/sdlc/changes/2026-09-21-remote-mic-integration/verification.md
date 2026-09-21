# Verification: Xiaomi remote wireless microphone in Utter

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/ci-basic-checks.sh` | Skipped | Exit 127: this Linux runner has no `swift` executable; the script cannot enter its Swift checks. |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `swift build` | Skipped | Exit 127: Swift is not installed in this Linux runner. |
| `swift test` (full suite) | Skipped | Exit 127: Swift is not installed in this Linux runner. |
| `swift test --filter RemoteMic` | Skipped | Exit 127: Swift is not installed in this Linux runner. |
| Real Xiaomi remote end-to-end | Not run | No hardware in this environment |

Environment note: this verification was run on Linux without Swift,
Xcode, or a Metal toolchain. The skipped Swift rows are environment skips,
not passing test results; macOS must rerun the build and test commands.

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
| P1: same-peripheral attempt isolation missing | Fixed in this increment | Each connection lifecycle installs source-bound peripheral and central delegate proxies. A central manager is retired after its lifecycle and a main-queue fence before a replacement manager is installed; every connection/state callback carries the owning proxy's attempt through the production route. `RemoteMicCallbackRoutingTests` retains old peripheral and central proxies and delivers late disconnect/control/didConnect/didFail events from the retired sources. |
| P0: normal release discarded the recording | Fixed | `RemoteMicReleaseDecision.applyRelease` drives the production release path: a committed recording is stopped (its WAV is needed), only an uncommitted start is cancelled (`RemoteMicReleasePathTests`). |
| P0: disabling the feature left the pipeline recording | Fixed | `RemoteMicShutdownDecision` stops the pipeline when a recording is active, because the bridge's release callback is suppressed once the setting is off. |
| P1: cold-model counterexample only tested a helper | Fixed | `RemoteMicPipelineIntegrationTests` drives the real `VoicePipeline.start` await through an injected model-load barrier and a capture spy, proving a released/superseded start never reaches recording or capture. |
| P1: idle audio polluted the next pre-roll | Fixed | `RemoteMicAudioRouting` (used by the bridge) drops audio with no live session; buffered only while starting (`RemoteMicAudioRoutingTests`). |
| P0: fallback leaked wanted state | Fixed | `RemoteMicWantedState` holds the want; a failed start calls `tearDownFailedStart()`, clearing the callback, ending capture, and dropping the temp file, so a later readiness cannot open the remote mic mid-system-session. Covered by `RemoteMicWantedStateTests`. |
| P1: handshake had no state gates | Fixed | `RemoteMicHandshake` requests capabilities only after both notifications are confirmed via `didUpdateNotificationStateFor`, once per attempt; connection and initialization timeouts (`connectionTimeout` 10 s, `initializationTimeout` 8 s) bound each attempt; `didFailToConnect` recovers; a monotonic `generation` rejects late callbacks. Covered by `RemoteMicHandshakeTests`. |
| P1: only pure protocol tests | Addressed in part | The gate and wanted-state are pure, injectable types with deterministic tests (20 total in the prior evidence set). Those Swift tests were not rerun on this Linux host; the CoreBluetooth transport still needs a real device. |

## Acceptance criteria

- Setting off keeps the existing path — pass by construction
  (`AudioCaptureManager.start` only consults the remote when
  `remoteMicEnabled`); Swift execution was not available in this Linux run.
- Setting on with a connected remote uses the decoded stream — implemented, but
  **not verified**: requires the physical remote.
- Setting on with no remote falls back to the system input — pass by
  construction (`RemoteMicCaptureManager.start` returns false unless the bridge
  is `.ready`), and the failure path now provably leaves no residue.
- Voice key starts and stops recording — implemented through the control-channel
  adoption path; **not verified on hardware**.
- Handshake ordering, attempt isolation, and timeouts are covered by
  deterministic tests (`RemoteMicHandshakeTests`,
  `RemoteMicAttemptIsolationTests`); this Linux run could not execute Swift.
- Source-bound same-peripheral late-event regression — specified in
  `swift test --filter RemoteMicCallbackRoutingTests`; the test retains the
  attempt-1 production peripheral and central delegate proxies, starts attempt
  2 on the same simulated object, and delivers old disconnect/control/
  didConnect/didFail events through those proxies. This Linux run could not
  execute it (exit 127: Swift unavailable); macOS must record the real result.
- Session cancel across the real pipeline path — prior unit-boundary evidence exists (`RemoteMicStartGuardTests`); Swift was not rerun on this Linux host. The live `VoicePipeline.start` await itself still needs a hardware/timing run.
- Localization parity and SDLC checks — pass; the basic CI script and Swift
  tests are skipped here with exit 127 because Swift is unavailable.

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
- **CoreBluetooth callback boundary.** Apple’s API gives central delegate
  methods a `CBPeripheral`, but no connection-attempt id; `didDisconnect` also
  ends further peripheral-delegate callbacks for that connection. The bridge
  therefore creates one central manager/delegate proxy per lifecycle, captures
  the attempt when discovery starts `connect`, retires that manager, and waits
  one `.main` queue turn before installing the replacement. Late callbacks
  from a retained old manager reach the old proxy and fail the source-attempt,
  manager-identity, and lifecycle-phase gates; the regression does not infer
  isolation from the replacement object’s mutable `state`. The guarantee is
  bounded by CoreBluetooth delivering callbacks through the manager’s `.main`
  queue and by all connection changes entering this proxy route. A direct
  unbound `CBCentralManagerDelegate` call is rejected for connection events;
  hardware validation must confirm the actual manager/proxy lifecycle.
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
