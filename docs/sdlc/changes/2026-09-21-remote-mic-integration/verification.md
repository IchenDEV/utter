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
| `swift build` | Pass | `Build complete! (32.00s)` with the Command Line Tools toolchain |
| `swift test` (full suite) | Pass | 643 tests, 10 skipped, 0 failures |
| `swift test --filter RemoteMicProtocolTests` | Pass | 10 tests, 0 failures |
| Real Xiaomi remote end-to-end | Not run | No hardware in this environment |

Test command note: this machine has no downloadable Metal toolchain, so the
Xcode build backend cannot compile `mlx-swift`'s Metal sources; the suite ran
with the Xcode toolchain and `--build-system native`.

## Acceptance criteria

- Setting off keeps the existing path — pass by construction
  (`AudioCaptureManager.start` only consults the remote when
  `remoteMicEnabled`); the existing 276-line file is otherwise unchanged and the
  full suite passes.
- Setting on with a connected remote uses the decoded stream — implemented, but
  **not verified**: requires the physical remote.
- Setting on with no remote falls back to the system input — pass by
  construction (`RemoteMicCaptureManager.start` returns false unless the bridge
  is `.ready`).
- ATVV parsing/decoding covered by deterministic tests — pass
  (`RemoteMicProtocolTests`, 10 tests).
- Localization parity and check scripts — pass.

## Residual risk

- **No hardware verification.** CoreBluetooth scan/connect/handshake, the
  remote's voice-key timing, and reconnect have not been exercised against a
  real device. This is the largest gap and must be closed by an independent
  verifier with the remote before the setting is enabled for users.
- **Licensing.** remote-mic-app is GPL-3.0-only; this is written as an
  independent implementation of the open ATVV profile and IMA/DVI ADPCM format,
  but a human must accept that position.
- The bridge assumes CoreBluetooth callbacks on the main queue and main-thread
  callers, matching the existing capture style; a future off-main caller would
  need the isolation tightened.
- `AudioCaptureActivity` thresholds were tuned for the built-in mic; the remote
  path uses the same gate with a user-adjustable gain.

## Decision

Blocked on independent hardware verification and the licensing decision. Do not
enable the setting for users until both are resolved. Human approval is recorded
separately.
