# Spec: Record through an external mic when the MacBook lid is closed

**Status:** approved
**Approved-by:** User (conversation)
**Approved-date:** 2026-10-01
**Upstream:** `intent.md` (approved 2026-10-01)

## Context

- `AudioCaptureManager.start(deviceID:levelUpdate:bufferUpdate:)` resolves the
  selected UID to a CoreAudio device, sets it on `AVAudioEngine.inputNode`'s
  audio unit, installs a tap, and writes buffers to one `AVAudioFile`. The same
  tap feeds `bufferUpdate` for streaming recognition.
- `AudioCaptureManager.availableMicrophones()` enumerates every device with
  input channels and reports the built-in mic even when the lid is closed, which
  is the root cause.
- `VoiceInputSettings.microphoneID` comes from `AppSettings` and is chosen in
  `GeneralSettingsView` via a picker.
- The wireless-remote path takes precedence when a remote session token is
  latched (`remoteMicSource.currentSessionToken`), and must stay untouched.
- `DeviceCapability` already imports IOKit, so IOKit is available without new
  dependencies or entitlements.

## Design

### 1. Lid state (`Sources/Audio/ClamshellState.swift`)

- `enum ClamshellState` exposes `static var isClosed: Bool` by reading the
  `AppleClamshellState` boolean from the `IOPMrootDomain` IORegistry entry.
- A pure `static func isClosed(fromClamshellState: Any?) -> Bool` parses the
  registry value so it is unit-testable without hardware.
- Missing entry (desktops, or inaccessible) yields `false`, so non-lid Macs are
  unaffected.
- No notification wiring: mid-session detection uses a bounded watchdog (below),
  which is simpler and deterministic to test.

### 2. Device catalog and classification

- `struct AudioInputDevice: Equatable { let uid: String; let name: String; let isBuiltIn: Bool }`.
- `AudioInputDevices.available() -> [AudioInputDevice]` enumerates devices with
  input channels and sets `isBuiltIn` from
  `kAudioDevicePropertyTransportType == kAudioDeviceTransportTypeBuiltIn`.
- `AudioInputDevices.systemDefaultUID() -> String?` reads
  `kAudioHardwarePropertyDefaultInputDevice`.
- External means `!isBuiltIn`; Continuity/iPhone, USB, Bluetooth, display, and
  aggregate inputs all qualify.

### 3. Pure resolver (`AudioInputResolver`)

`static func resolve(devices:preferredUID:systemDefaultUID:lidClosed:) -> Resolution`
where `Resolution = .use(uid: String) | .unavailable`.

Rules, in order:

1. A device is *usable* unless it is built-in and `lidClosed`.
2. If `preferredUID` names a usable device, use it.
3. Otherwise, if the system default is a usable device, use it.
4. Otherwise, if any non-built-in device is usable, use the first one.
5. Otherwise, `.unavailable`.

This keeps the user's explicit choice authoritative when it works, and only
substitutes when the chosen input is the disconnected built-in microphone (or
the chosen device is gone).

### 4. Capture start (`AudioCaptureManager`)

- `start(...)` adds a `forcedUID` resolution step before `setInputDevice`:
  resolve from `AudioInputDevices.available()`, `preferredUID = deviceID`,
  `systemDefaultUID`, and `ClamshellState.isClosed`.
- On `.unavailable`, return a typed failure instead of a bare `false`:
  `enum CaptureStartFailure { case permissionDenied, noUsableInput, engineFailed }`.
  Existing `Bool` call sites migrate to `Result<(), CaptureStartFailure>`; the
  remote-spy seam maps `noUsableInput`/`permissionDenied` to the current
  `pipeline.mic_unavailable` behavior.
- On success, record the resolved UID as `activeInputUID` and that a fallback
  was used, for numeric diagnostics only.

### 5. Mid-session failover

- While a local capture is running, a serial-queue watchdog re-evaluates the
  resolver every 0.5s with current devices and lid state (plus an
  `AVAudioEngineConfigurationChange` observer for device removal).
- If the active device is no longer usable and an alternative resolves, switch:
  stop the engine and tap, set the new device, restart, and re-install the tap.
  Level and buffer callbacks stay wired so streaming and the overlay are
  uninterrupted.
- Recording file handling: append into the existing `AVAudioFile` when the new
  device's format matches the file's. When it differs, convert buffers with
  `AVAudioConverter` to the file's processing format before writing. If
  conversion cannot be created, fail the session rather than lose audio.
- If no alternative resolves mid-session, stop capture and report the same
  `noUsableInput` failure so the pipeline ends with a localized error.

### 6. Pipeline and UI

- `VoicePipeline+Recording.swift` maps `noUsableInput` to a new localized
  message `pipeline.mic_clamshell_no_input`; `permissionDenied` keeps
  `pipeline.mic_failed_permissions`. Mid-session failure calls `stopRecording`
  and shows the message.
- Add a brief status message when a mid-session switch succeeds, reusing the
  overlay status channel. (Confirms intent open question: signal, not silent.)
- No new settings screen; the existing microphone picker stays as the preference
  source. Localization keys are added to both `en.lproj` and `zh-Hans.lproj`.

## Safety and failure modes

- Apple's hardware disconnect cannot be overridden; this change only reroutes.
- Never treat a silent built-in capture as success: every unusable-input path
  ends in a switch or an error.
- Falling back to Bluetooth/Continuity can add latency and reduce quality; the
  substitution is automatic but only when the selected input is unusable.
- A switch may drop up to the watchdog interval (≤0.5s) of audio at the seam;
  acceptable and recorded as residual risk.
- Diagnostics stay numeric (`AudioCaptureDiagnostics`); no samples, no
  transcripts, no new permissions or TCC prompts.
- If engine restart or format conversion fails mid-failover, the session ends
  with an error instead of continuing silently.

## Test strategy

- `AudioInputResolver` unit tests: lid open/closed, `preferredUID` nil, preferred
  external, preferred built-in with an external present, preferred built-in with
  none present, chosen device missing, desktop (no built-in).
- `ClamshellState.isClosed(fromClamshellState:)` parse tests: true/false/nil.
- `AudioInputDevice` classification test with an injected transport type.
- Pure `MicFailoverDecision.shouldSwitch(activeUID:resolution:)` tests covering
  continue vs. switch vs. fail.
- Manual docked-device check: start with lid closed, close lid mid-session,
  remove all external inputs.

## Rollout and rollback

- Internal behavior change; ships with the next normal release. No migration.
- Rollback: revert the change set. No persisted state is written, so reverting is
  clean and immediate.
- Observation: numeric diagnostics confirm which input was used and whether a
  fallback occurred; no user audio is logged.
