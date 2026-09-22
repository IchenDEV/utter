# Intent: Xiaomi remote wireless microphone in Utter

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** —

## Problem

The user wants the wireless-mic capability of `IchenDEV/remote-mic-app` inside
Utter so a Xiaomi Bluetooth Remote 2 Pro can act as Utter's microphone without
installing a second application. remote-mic-app needs its own app plus a
BlackHole-derived `MiRemoteV 2ch` audio driver, and it only feeds that driver;
the user then has to point each target app at the virtual device.

## Outcome

When enabled, Utter connects to the remote over Bluetooth, decodes the remote's
ATVV voice stream in-process, and uses those samples as its recording input.
The remote's voice key drives Utter's recording directly through the ATVV
control channel (`AUDIO_START`/`AUDIO_STOP`), which is the interaction model the
device uses when the host has not opened the microphone itself; no HID key remap
or Input Monitoring permission is involved. While a recording is active the
audio comes from the remote instead of a CoreAudio device. No virtual audio
driver and no second app are required.

## Scope

Affected: a new `Sources/RemoteMic/` module (ATVV profile, ADPCM decoder, BLE
central, capture source), `AudioCaptureManager` source selection, the General
settings audio section, Bluetooth usage text and entitlement, and localizations.

Non-goals: remote button remapping, battery display, sending the remote's audio
to other apps, replacing the existing wired/Built-in microphone path, or changing
the speech engines.

## Constraints

- Default off; enabling it is the only thing that may trigger Bluetooth access.
- No new package dependency; CoreBluetooth only.
- Samples are processed in memory, matching Utter's no-audio-upload posture.
- The existing system-microphone path must stay selectable and unaffected.
- A remote that is unavailable, unauthorized, or unsupported must fall back to
  the system input instead of failing the recording.

## Acceptance criteria

- With the setting off, recording is byte-for-byte the existing path.
- With the setting on and a remote connected, recording uses the decoded 16 kHz
  mono stream; the WAV, activity gate, level meter, and streaming buffers behave
  like the built-in path.
- With the setting on and no remote connected, recording still succeeds with the
  system input.
- The ATVV capability parsing, framing, ADPCM decode, and PCM post-processing are
  covered by deterministic unit tests.
- Localizations stay in parity and the two check scripts pass.

## Open questions

- Licensing: remote-mic-app's app code is GPL-3.0-only while Utter is MIT. This
  SDLC record makes no determination about whether the implementation,
  attribution, or distribution position is acceptable. A human licensing owner
  must review the provenance and decide whether to accept, attribute, rework, or
  reject the change before the feature is enabled or distributed.
- Hardware: the remote's firmware behavior (voice-key timing, reconnect) can only
  be confirmed on a real device by someone with the remote.
