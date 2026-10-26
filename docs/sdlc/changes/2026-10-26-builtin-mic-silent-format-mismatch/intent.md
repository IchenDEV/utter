# Intent: Fix silent capture from the built-in microphone (hardware format mismatch)

**Status:** approved
**Approved-by:** User, explicit approval in this conversation (answered the approval question: approve)
**Approved-date:** 2026-10-26
**Upstream:** —
**Risk:** Medium, core capture behavior; corrective intent for a production regression in v0.0.59

## Problem

On a MacBook Pro running Utter v0.0.59 the built-in microphone records nothing.
Every hotkey session ends as `failed` within about 250 ms of release, with no
transcript and no actionable message.

Evidence from the unified log of the running app (pid 19716) and a standalone
reproduction on the same machine:

- Three consecutive sessions (17:18:21, 17:18:24, 17:18:50) each log
  `Format mismatch: input hw <1 ch, 44100 Hz>, client format <1 ch, 48000 Hz>`
  followed by `Failed to create tap, config change pending!`. The engine then
  reports `start, was running 0` and later `stop, was running 1`, so it runs
  without a working tap and no audio frames arrive.
- `AudioCaptureManager.startLocal` selects the device with `setInputDevice(uid:)`
  and then reads the tap format from `inputNode.outputFormat(forBus: 0)`.
  `AVAudioEngine` caches that value from the default aggregate device it creates
  on first access to `inputNode` (48 kHz, clocked to the 48 kHz output). The
  built-in microphone runs at 44.1 kHz, so the tap format no longer matches the
  hardware.
- Standalone reproduction (same sequence, RMS only, nothing stored):

  | Tap format source | Tap rate | Frames in 2 s | Peak |
  |---|---|---|---|
  | `inputNode.outputFormat(forBus: 0)` (current code) | 48000 Hz | 0 | 0 |
  | `inputNode.inputFormat(forBus: 0)` (hardware) | 44100 Hz | 83790 | 0.027 |

- Regression origin: before `8d271d6` (first shipped in v0.0.49) the code called
  `setInputDevice` only when the user had explicitly chosen a microphone. Since
  that commit the call runs on every start, including the system default device,
  so any user whose input hardware rate differs from the engine's cached rate is
  exposed. Behavior of releases before v0.0.49 with an explicit selection was
  not re-tested.
- The same stale format is also used for the recording WAV, so a mismatched
  rate would additionally mislabel the audio handed to ASR.
- The mismatch is only logged by AVFoundation; the app gets no error, so the
  failure surfaces as "no speech" instead of a capture error.

## Outcome

Recording from the built-in microphone, the system default input, or an explicit
selection captures audio whenever the device itself delivers audio, regardless of
whether its sample rate differs from the engine's default aggregate rate. The
recording file and streaming buffers are labeled with the rate actually captured.

## Scope

- `Sources/UtterAudio/Native/AudioCaptureManager.swift`, `+Tap`, and `+Devices`:
  derive the capture format from the hardware after the input device is set, for
  both the initial start and the mid-session failover switch.
- A deterministic, unit-testable rule for choosing the tap format.
- A guardrail for a capture that is running but receives no frames: refresh the
  capture format and restart the tap once, then report a capture error if frames
  still do not arrive (decided by the user, see Decisions).

Non-goals: remote microphone path, lid-closed failover policy, device picker UI,
sensitivity thresholds, ASR or text processing, and migrating off the deprecated
`installTap` API.

## Constraints

- No new permission, entitlement, or privacy surface. Diagnostic logging may
  contain numeric formats and counts only, never audio or transcript content.
- Must keep working for devices whose hardware rate equals the cached rate, for
  Bluetooth and USB inputs, and after a mid-session device switch.
- Keep each file under 300 lines and follow the existing functional style.
- This is a production regression: it must ship with a regression test or
  deterministic guardrail. A physical mismatch cannot be produced in CI, so the
  rule that selects the format must be testable without hardware.
- Keep every stage pending until the user approves that stage.

## Acceptance criteria

- On the affected machine (built-in microphone 44.1 kHz, default aggregate
  48 kHz) a real-window hotkey recording delivers non-zero frames, a level above
  the gate for normal speech, and a transcript; the unified log contains no
  `Format mismatch` or `Failed to create tap` for that session.
- The tap format and the recording file format both come from the selected
  device's hardware format read after device selection; a recorded WAV reports
  the same sample rate as the captured samples.
- The mid-session failover switch (`switchInput`) uses the same rule, and a
  fallback device with a different rate still produces a correctly converted
  recording.
- A unit test fails on the old behavior and passes on the new one: given a cached
  client format of 48 kHz and a hardware format of 44.1 kHz, the selected tap
  format is 44.1 kHz; invalid hardware formats fall back as specified in the spec.
- The remote microphone path, lid-closed failover, and device picker behave as
  before (existing tests keep passing).
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and
  `swift test` pass. A release-style build passes because capture runtime changes.
- A capture that runs but delivers zero frames for about 1.5 s is restarted once
  with a freshly read hardware format; if it still delivers none, the user sees a
  localized capture error (both `en` and `zh-Hans`) instead of "no speech". The
  retry and the error are covered by deterministic tests of the decision logic.
- Rollback is reverting this change; no data or settings migration is involved.

## Decisions

- 2026-10-26, user: add a silent-capture guardrail that retries once with a
  refreshed hardware format before reporting a capture error.
- 2026-10-26, user: approved this intent.

## Open questions

- Whether handling `AVAudioEngineConfigurationChange` is needed. The
  reproduction received frames with the hardware format even though a
  configuration-change notification fired, so the default is not to add it unless
  the spec finds a concrete failure.
