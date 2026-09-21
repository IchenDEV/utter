# Spec: Xiaomi remote wireless microphone in Utter

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `intent.md`

## Context

`AudioCaptureManager` owns the only capture path: it taps `AVAudioEngine`'s input
node at the device's native format, writes a temp WAV, accumulates
`AudioCaptureActivity`, and forwards copied buffers to the streaming engine.
`VoicePipeline` and `InputSessionCoordinator` each own one instance and read
`lastRecordingURL` / `lastActivity` after stopping. `AppSettings` persists user
preferences; the General tab hosts the microphone picker.

The remote speaks the ATVV profile over GATT: service `ab5e0001-…`, transmit,
audio, and control characteristics; a `GET_CAPABILITIES` request (`0x0A 01 00 00
03 03`) yields a `0x0B` capability frame carrying version, codec mask, and frame
size. Audio notifications are IMA/DVI ADPCM nibbles that decode to 16 kHz mono
`Int16`. Frames are fixed-size and the predictor/step state persists until a
`0x0A` sync packet resets it. Only 16 kHz is accepted.

## Design

`Sources/RemoteMic/` (all new, no dependency):

- `RemoteMicProtocol` — profile UUIDs, opcodes, capability frame parsing, ADPCM
  decoder, frame accumulator, PCM smoothing/gain. Pure and unit-tested.
- `XiaomiRemoteMicBridge` — `CBCentralManager` with `queue: .main`. Scans for
  the ATVV service, connects, discovers the three characteristics, subscribes to
  audio/control, requests capabilities, sends microphone open/close, decodes
  audio, and republishes state through `ObservableObject`. Reconnects with
  exponential backoff while the feature is active. All callbacks arrive on the
  main thread, which matches the codebase's existing non-isolated capture style.
  The handshake is ordered and bounded: `RemoteMicHandshake` only allows the
  capability request after both notifications are confirmed by
  `didUpdateNotificationStateFor`, a connection and an initialization timeout
  bound each attempt, `didFailToConnect` recovers, and a monotonic `generation`
  rejects late callbacks from a failed attempt.
- `RemoteMicWantedState` — the "does a session want audio" invariant, shared by
  the bridge and the capture manager so a failed start cannot leave a latent
  want that a later readiness would act on.
- `RemoteMicCaptureManager` — mirrors the capture surface of
  `AudioCaptureManager`: temp 16 kHz mono WAV, `AudioCaptureActivity`, level
  callback, streamed `AVAudioPCMBuffer`s.

`AudioCaptureManager` gains an optional `remoteMicSource` and a
`usesRemoteMic` flag. `start` tries the remote first when
`AppSettings.remoteMicEnabled` is on and the bridge is ready; otherwise it takes
the existing AVAudioEngine path. `lastRecordingURL` / `lastActivity` /
`cleanupLastRecording` / `stop` dispatch to whichever source is active, so the
pipeline and integration coordinator need no changes. `VoicePipeline` and
`InputSessionCoordinator` inject `RemoteMicCaptureManager.shared`.

`AppSettings` adds `remoteMicEnabled` (default false) and `remoteMicGainDB`
(default 12, 0–24). `AppDelegate` observes the setting and activates/deactivates
the bridge; `applicationWillTerminate` deactivates it. The General tab adds the
toggle, a live connection state, and the gain slider, and disables the system
device picker while the remote is enabled.

The remote's voice key arrives on the ATVV control channel
(`MIC_OPEN_REQUEST`/`STREAM_START`), so `AppDelegate` maps it onto the same
`startRecording`/`stopRecording` path the configured hotkey uses. Holding the
remote key records through Utter; releasing it stops. This avoids a separate
device-level HID F5→Fn remap and the Input Monitoring permission such a remap
would need.

## Safety and failure modes

- Default off. Bluetooth is only touched once the user enables the setting, so
  apps that never opt in never see a Bluetooth permission prompt.
- `NSBluetoothAlwaysUsageDescription` and `com.apple.security.device.bluetooth`
  are declared; the app is not sandboxed, so no other capability changes.
- Audio is decoded in memory and written only to Utter's temp recording file;
  it is never transmitted. Logging is state-only (no audio, no device IDs).
- If the remote is not ready, unauthorized, unsupported, or the 16 kHz codec is
  absent, `RemoteMicCaptureManager.start` returns false and
  `AudioCaptureManager` falls back to the system input.
- Disconnect or stream stop clears the decoder/accumulator and drops the
  partial frame, so a later session cannot inherit stale ADPCM state.
- A start that fails after wanting audio tears down the callback, the want, and
  the temp file, so a system-input fallback cannot be hijacked by a later
  readiness.

## Test strategy

`RemoteMicProtocolTests` covers capability parsing (v1.0 and 8 kHz rejection),
control command construction, ADPCM nibble order and cross-frame predictor
continuity with sync reset, Int16 clamping, frame accumulation, and PCM
smoothing/gain. `RemoteMicHandshakeTests` covers the subscription gate (no
capability request before both notifications are confirmed), the
request-once-per-attempt rule, 8 kHz rejection, reset isolation, and readiness.
`RemoteMicWantedStateTests` covers the fallback invariant. CoreBluetooth
transport behavior still needs a real remote; the verification artifact records
that as residual risk.

## Rollout and rollback

Ships default-off with the next Utter release. Rollback is reverting the commit;
with the setting off the new code paths are unreachable. If the setting were
already on, reverting leaves `remoteMicEnabled` unread and capture returns to the
system device.

## Verification requirements for this lane

High risk (a new device permission and an external protocol). Before enabling it
for users: independent verification on a real remote, explicit confirmation that
the licensing position is acceptable, and a manual check of connect, record,
disconnect, and reconnect behavior.
