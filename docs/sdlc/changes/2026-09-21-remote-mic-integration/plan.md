# Plan: Xiaomi remote wireless microphone in Utter

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `spec.md`

## Work items

- [x] `RemoteMicProtocol`: UUIDs, opcodes, capability parsing, ADPCM decoder,
      frame accumulator, PCM smoothing/gain.
- [x] `RemoteMicHandshake`: subscription gate, request-once, readiness.
- [x] `RemoteMicWantedState`: no residue after a failed start.
- [x] Voice key on the ATVV control channel drives Utter's recording path.
- [x] Connection/initialization timeouts, `didFailToConnect`, generation guard.
- [x] `XiaomiRemoteMicBridge`: CoreBluetooth central, ATVV handshake, streaming,
      reconnect, observable state.
- [x] `RemoteMicCaptureManager`: WAV/activity/level/buffer capture surface.
- [x] `AudioCaptureManager` source selection with system-input fallback.
- [x] Inject the shared remote source in `VoicePipeline` and
      `InputSessionCoordinator`.
- [x] `AppSettings.remoteMicEnabled` / `remoteMicGainDB` with persistence.
- [x] Settings toggle, live state, gain; `AppDelegate` activate/deactivate.
- [x] `NSBluetoothAlwaysUsageDescription` and the Bluetooth entitlement.
- [x] en/zh-Hans strings, `RemoteMicProtocolTests`, `RemoteMicHandshakeTests`,
      `RemoteMicWantedStateTests`, `RemoteMicSessionTests`,
      `RemoteMicPreRollTests`.
- [x] Session latch (`RemoteMicSession`) so a release beating the start cancels
      it, and a bounded pre-roll (`RemoteMicPreRoll`) so the opening word is not
      clipped.
- [x] `endCapture` closes the microphone once in every phase; `deactivate`
      invalidates the session.
- [x] Capability responses require a prior request; `didUpdateValueFor` checks
      peripheral identity.
- [x] Correct `0x08` to `START_SEARCH` and cite the AOSP ATVV reference firmware.

## Verification plan

- [x] `bash scripts/ci-basic-checks.sh`
- [x] `bash scripts/sdlc-checks.sh`
- [x] `swift test` (full suite)
- [ ] Real Xiaomi Bluetooth Remote 2 Pro: pair, enable, record via the remote's
      voice key, then disconnect and reconnect mid-session.
- [ ] Independent reviewer confirms the GPL/MIT licensing position and the
      permission/privacy path.

## Human gates

- Licensing decision on reusing the ATVV capability from the GPL-3.0 project
  (this implementation is independent, but a human must accept it).
- Independent verification on real hardware before enabling the setting for
  users.
- Merge approval for a change that adds a device permission.
