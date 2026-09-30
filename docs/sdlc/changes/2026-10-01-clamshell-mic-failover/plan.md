# Plan: Record through an external mic when the MacBook lid is closed

**Status:** approved
**Approved-by:** User (conversation)
**Approved-date:** 2026-10-01
**Upstream:** `spec.md` (approved 2026-10-01)

## Work items

- [ ] Add `Sources/Audio/ClamshellState.swift` with `isClosed` and a pure
      `isClosed(fromClamshellState:)` parser.
- [ ] Add `Sources/Audio/AudioInputDevice.swift` with `AudioInputDevice`,
      `AudioInputDevices.available()`, `systemDefaultUID()`, and transport-type
      classification.
- [ ] Add `Sources/Audio/AudioInputResolver.swift` with the pure `resolve(...)`
      rules and a `MicFailoverDecision` helper.
- [ ] Extend `AudioCaptureManager` to resolve the start device via the resolver
      and return `CaptureStartFailure` instead of `Bool`.
- [ ] Add the local-capture watchdog (0.5s) plus
      `AVAudioEngineConfigurationChange` observer for mid-session failover,
      including `AVAudioConverter` handling when the device format changes.
- [ ] Update `VoicePipeline+Recording.swift` (and the remote-spy seam) to map the
      new failure cases to localized messages and to surface a brief status
      message when a switch succeeds.
- [ ] Add `pipeline.mic_clamshell_no_input` to `en.lproj` and `zh-Hans.lproj`.
- [ ] Add unit tests for the resolver, clamshell parser, device classification,
      and failover decision.
- [ ] Run the automated checks and the manual docked-device verification.

## Verification plan

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] Real docked MacBook: built-in mic + lid closed records from an external
      input; mid-session lid close continues the session; no external input
      produces the localized error.
- [ ] `bash scripts/build-app.sh` if the capture change alters packaging or
      runtime dependencies (not expected; run if in doubt).

## Human gates

- Intent approval before design or implementation starts.
- Spec approval (medium risk: user-visible audio behavior and a new failure
  message) before implementation starts.
- Plan approval before implementation.
- Verification approval and PR review before merge.
