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
| `swift test` (full suite) | Pass | 671 executed, 10 skipped, 0 failures |
| `swift test --filter RemoteMic` | Pass | 34 tests, 0 failures |
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
- Handshake ordering and timeouts covered by deterministic tests — pass.
- Localization parity and check scripts — pass.

## Residual risk

- **No hardware verification.** Pairing, scan/connect, the two notification
  subscriptions, the voice key press/release, first and last frame, session
  teardown on disconnect, reconnect, and real 16 kHz audio all still need a
  person with the remote. This is the largest gap.
- **Licensing.** `IchenDEV/remote-mic-app` is GPL-3.0-only and the reviewer found
  the protocol implementation structurally close to it. A human must resolve
  attribution/licensing before any distribution; the setting stays default off.
- The bridge assumes CoreBluetooth callbacks on the main queue and main-thread
  callers, matching the existing capture style.
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
