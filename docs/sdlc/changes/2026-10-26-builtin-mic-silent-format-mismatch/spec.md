# Spec: Capture from the device's hardware format and guard against silent capture

**Status:** approved
**Approved-by:** User, explicit approval in this conversation (answered the approval question: approve)
**Approved-date:** 2026-10-26
**Upstream:** `intent.md` (approved 2026-10-26)

## Context

- `AudioCaptureManager.startLocal` resolves a device UID with
  `AudioInputResolver`, calls `setInputDevice(uid:)` (sets
  `kAudioOutputUnitProperty_CurrentDevice` on `engine.inputNode.audioUnit`), then
  reads `inputNode.outputFormat(forBus: 0)` and uses that single value for the
  `AVAudioFile` settings and for `installCaptureTap()`, which reads it again.
  `switchInput(to:)` (mid-session failover) repeats the pattern.
- First access to `engine.inputNode` makes `AVAudioEngine` create a default
  aggregate device (`CADefaultDeviceAggregate`) and cache its format. On the
  affected machine that is 48 kHz because the aggregate is clocked by the 48 kHz
  output. `setInputDevice` then moves the unit to the built-in microphone
  (44.1 kHz), but `outputFormat(forBus: 0)` keeps returning the cached 48 kHz.
  `installTap` with 48 kHz against 44.1 kHz hardware logs
  `Format mismatch` / `Failed to create tap, config change pending!` and installs
  nothing. The engine still starts, so `start` returns success and zero frames
  arrive. Evidence: `evidence/` (unified-log extract, repro script and output).
- `inputNode.inputFormat(forBus: 0)` returns the hardware format (44.1 kHz) at the
  same point. Tapping with it delivered 83 790 frames in 2 s on the same machine.
- Before `8d271d6` (v0.0.49) `setInputDevice` ran only for an explicit user choice.
  Since then it runs on every start. `AudioInputResolver` stays unchanged.
- Existing seams reused: `write(_:)` already converts a buffer whose format differs
  from `recordingFormat`; `failoverTimer` already runs `evaluateInputHealth()`
  every 0.5 s on the main run loop; `onInputUnavailable` already ends the session
  with a localized error; the streaming normalizers build their converter from
  each buffer's own format, so they accept any rate.

## Design

### 1. Hardware-first capture format (`Sources/UtterAudio/CaptureFormatSelection.swift`)

```swift
enum CaptureFormatSelection {
    /// Format to tap and record after the input device was set.
    static func tapFormat(hardware: AVAudioFormat, client: AVAudioFormat) -> AVAudioFormat?
}
```

- Returns `hardware` when its sample rate is finite and positive and it has at
  least one channel; otherwise `client` under the same validity test; otherwise
  `nil`. The result is the tap format and the recording-file format.
- Pure and hardware-free, so it is unit-testable with synthetic `AVAudioFormat`s.
- `AudioCaptureManager` gets one helper, `currentCaptureFormat()`, that calls it
  with `inputNode.inputFormat(forBus: 0)` and `inputNode.outputFormat(forBus: 0)`
  and logs, only when the two sample rates differ, one numeric line such as
  `capture format 44100 Hz differs from engine format 48000 Hz; using hardware`.
- `startLocal` calls `currentCaptureFormat()` once after `setInputDevice`, uses the
  result for `AVAudioFile` and passes it to `installCaptureTap(format:)`. A `nil`
  result returns `.engineFailed` as today's invalid-format guard does.
- `installCaptureTap` takes the format as a parameter instead of re-reading it, so
  the file and tap can never disagree. `switchInput` computes the format after its
  `setInputDevice` and passes it in. The recording file keeps its original format
  and `write(_:)` converts when a fallback device runs at another rate (existing
  behavior).

### 2. Silent-capture guardrail (`Sources/UtterAudio/CaptureLiveness.swift`)

```swift
enum CaptureLivenessAction: Equatable { case healthy, wait, retry, fail }

enum CaptureLiveness {
    static let graceSeconds: TimeInterval = 1.5
    static let maxRetries = 1
    static func decide(elapsed: TimeInterval, framesReceived: Int, retriesUsed: Int)
        -> CaptureLivenessAction
}
```

- `framesReceived > 0` is `healthy`. A non-finite or negative `elapsed`, or
  `elapsed < graceSeconds`, is `wait`. At or after the grace period with zero
  frames it is `retry` while `retriesUsed < maxRetries`, otherwise `fail`.
- `AudioCaptureManager` adds `captureStartedAt: Date` and `livenessRetries: Int`,
  reset in `startLocal` and `stop`. `evaluateInputHealth()` keeps its failover
  decision first; only when that decision is `.keep` does it evaluate liveness
  from `lastActivity.frameCount` (read under `recordingLock` via the existing
  accessor). Remote capture is skipped, as it is today.
- `retry`: increment `livenessRetries`, reset `captureStartedAt`, and rebuild the
  tap on the same device through a shared `restartCapture(on:)` extracted from
  `switchInput` (remove tap, stop, `setInputDevice`, fresh format, install tap,
  prepare, start). `switchInput` becomes `restartCapture` plus the fallback log
  and `onAutoSwitch`; the retry path does not call `onAutoSwitch`, so the user
  sees no "switched input" notice. If the restart itself fails, treat it as `fail`.
- `fail`: stop capture and call `onInputUnavailable(.noAudioReceived)`.

### 3. Error reporting

- New `AudioCaptureStartFailure.noAudioReceived` with the message key
  `pipeline.mic_no_audio`:
  - en: "The microphone is not delivering audio. Check the selected input device
    or whether another app is using it."
  - zh-Hans: "麦克风没有输出音频，请检查所选输入设备，或确认没有被其他应用占用。"
- `CaptureCallbacks.inputUnavailable` becomes `(AudioCaptureStartFailure) -> Void`
  (default `{ _ in }`). Updated call sites: `CaptureCallbackGate`,
  `LocalCaptureDriver`, `VoiceSessionJob+Capture` (uses the passed reason instead
  of the hard-coded `.noUsableInput`), and the two test invocations in
  `VoiceWorkflowTests`. Existing paths (`handleInputUnavailable()` from lid-closed
  failover and the silent-remote fallback) pass `.noUsableInput`, so their
  behavior is unchanged.
- `SessionFailurePresentation` needs no new recovery action: the message already
  names the next step.

### Non-goals and rejected alternatives

- Not forcing the engine's cached format by recreating `AVAudioEngine` per start:
  heavier and changes device-enumeration timing for the remote path.
- Not subscribing to `AVAudioEngineConfigurationChange` (the intent's open
  question). The repro received frames across a configuration-change
  notification, and the liveness retry already recovers a stalled engine.
  Revisit only if verification finds a concrete failure.
- Not migrating off the deprecated `installTap` overload.

## Safety and failure modes

- Privacy: no new data or permission. New log lines carry sample rates and frame
  counts only. The diagnostic evidence stores no audio and no transcript.
- Invalid hardware format (0 Hz, such as a device still negotiating): falls back to
  the client format, then `nil` (`.engineFailed`). Behavior is no worse than today.
- False positive of the guardrail: a healthy input delivers a buffer roughly every
  100 ms even when silent, so 1.5 s without any frame indicates a stall. A device
  that needs longer to start (for example a Bluetooth headset switching profile)
  gets one restart, then an error after about 3 s; the user can retry. A restart
  that disturbs such a negotiation is the main residual risk and is recorded in
  `verification.md`.
- A session released before the 1.5 s grace period never trips the guardrail. With
  the format fix the root cause is gone; see Open questions for the residual case.
- Concurrency: liveness runs on the main run loop like the existing failover
  check; the tap callback keeps using `recordingLock`; `restartCapture` reuses the
  remove-tap/stop/start order that `switchInput` already uses.
- Lid-closed failover and remote mic: decision order is unchanged (failover first,
  liveness only on `.keep`); the remote path is skipped by the existing guard.

## Test strategy

| Acceptance criterion | Evidence |
|---|---|
| Hardware format drives tap and file | `CaptureFormatSelectionTests`: 44.1 kHz hardware vs 48 kHz client returns 44.1 kHz (fails on the old behavior); equal formats; invalid hardware falls back to client; both invalid returns `nil`; channel count honored |
| Zero-frame retry then error | `CaptureLivenessTests`: frames present at any elapsed time is `healthy`; before and at the 1.5 s boundary with zero frames; first expiry is `retry`; after one retry is `fail`; negative and NaN elapsed are `wait` |
| Localized capture error | `VoiceWorkflowTests`: `inputUnavailable(.noAudioReceived)` surfaces `AudioCaptureStartFailure.noAudioReceived.localizedDescription`; existing `.noUsableInput` tests updated and still pass; `ci-basic-checks.sh` localization parity |
| Real hardware fix | Debug build via `scripts/build-and-run.sh --verify` on the affected MacBook: hotkey recording yields a transcript; unified log has no `Format mismatch` / `Failed to create tap`; repeat with the system default input and with an explicitly selected built-in microphone |
| Other devices unaffected | Manual: record once each with another available input whose rate matches the cached one, and with a device switch from the picker; mid-session failover logic is covered by the existing resolver tests |
| Regression boundaries | Full `swift test`, `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and a release-style build (`bash scripts/build-app.sh`) |

## Rollout and rollback

- Ship as the next patch release after the PR is approved; releasing is a separate
  protected step and is not authorized by this spec.
- Observation after release: the unified-log lines `Format mismatch` and
  `Failed to create tap` (macOS `log show`) must no longer appear for Utter, and
  the new `pipeline.mic_no_audio` error should be rare.
- Stop condition: any report of repeated "microphone is not delivering audio" on a
  working device, or a recording regression on a device that previously worked.
- Rollback: revert the change. No settings, data, or migration is involved. If
  only the guardrail misbehaves, revert it separately; the format fix is
  independent.

## Decisions

- 2026-10-26, user: approved this spec.
- 2026-10-26, user: sessions shorter than the 1.5 s grace period that receive zero
  frames keep reporting "no speech" in this change; a finish-time zero-frame
  check is out of scope.

## Open questions

None.
