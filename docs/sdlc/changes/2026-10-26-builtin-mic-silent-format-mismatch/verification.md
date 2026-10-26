# Verification: Capture from the device's hardware format and guard against silent capture

**Status:** approved
**Approved-by:** User, explicit approval in this conversation (answered the approval question: approve, commit and push, open PR)
**Approved-date:** 2026-10-26
**Upstream:** [plan.md](plan.md)

## Candidate and environment

- Date: 2026-10-26. Branch `cursor/fix-builtin-mic-silent`, base `origin/main` at
  `fd87c34` (v0.0.59), uncommitted working tree.
- Machine: MacBook Pro, Apple Silicon, macOS 27, lid open. Built-in microphone at
  44.1 kHz; the engine's default aggregate device at 48 kHz (output is 48 kHz).
  Other inputs present: iPhone Microphone, `LarkAudioDevice`, `MiRemoteV 2ch`.
- The user's installed Utter v0.0.59 and its permissions were not touched: no
  `build-and-run.sh` (it runs `pkill -x Utter` and launches a differently signed
  copy), no install. Hardware checks drove the real `AudioCaptureManager` from a
  temporary XCTest that was deleted before commit.

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Root cause reproduced on the unmodified code | Pass (bug reproduced) | `evidence/utter-0.0.59-unified-log-extract.txt` (three sessions with `Format mismatch` and `Failed to create tap`); `evidence/mic-format-repro-output.txt` (0 frames with `outputFormat`, 83 790 with `inputFormat`) |
| New unit tests (`CaptureFormatChoiceTests` 5, `CaptureLivenessTests` 6) | Pass | `swift test --filter UtterAudioTests`: 31 tests, 0 failures. Before the change these types did not exist; the behavioral red state is the hardware run below |
| `VoiceWorkflowTests` incl. new `testSilentCaptureReportsNoAudioReceivedInsteadOfNoUsableInput` | Pass | Full run, 0 failures |
| `swift test --jobs 4` (full) | Pass, exit 0 | 15 XCTest bundles, 1 468 cases, 24 skipped, 0 failures; 1 Swift Testing test passed |
| Real hardware, fixed code | Pass | `evidence/hardware-probe-output.txt`: explicit built-in 194 040 frames, system default 198 450 frames over 4.4 s, WAV rate 44 100 Hz, frames equal file length, no error |
| Real hardware, old behavior simulated | Red as expected | No frames; the restart path raised an Objective-C exception from `installTap`. Led to the restart-only rule `allowClientFallback: false` |
| Real hardware, guardrail retry recovers | Pass | First tap forced stale once: restart after 1.5 s, frames flow, no error, file converted to the original 48 kHz format with matching duration |
| Real hardware, guardrail reports persistent stall | Pass | Tap not reinstalled on restart: `noAudioReceived` after about 3 s, capture stopped |
| `bash scripts/sdlc-checks.sh` | Pass, exit 0 | Bundle stages ordered; intent, spec, plan approved with approver and date |
| `bash scripts/ci-basic-checks.sh` | Pass, exit 0 | Includes SDLC artifacts, localization key parity (`pipeline.mic_no_audio` in `en` and `zh-Hans`), identifiers, and repository invariants |
| `bash scripts/build-app.sh --app-only` | Pass, exit 0 | Release-style build, Sparkle embedding, signature and artifact verification passed. Signed ad hoc (no identity on this machine), so not notarized and not installable over the user's app |
| `git diff --check` | Pass, exit 0 | No whitespace errors |

## Acceptance criteria

- Real-window hotkey recording on the affected machine delivers frames, a
  transcript, and no `Format mismatch` — **partly met.** The real capture class
  delivered frames at the correct rate on this machine for both the system default
  and an explicit built-in selection. A full hotkey session through the installed
  Utter UI was not run, because that needs a build with the user's signing
  identity; this remains for the user after the next release build.
- Tap and file formats come from the hardware format read after device selection
  — **met.** `currentCaptureFormat()` feeds both; WAV rate equals captured rate.
- `switchInput` uses the same rule and converts for a different-rate fallback —
  **met by construction and by the converted-file run above** (`restartCapture`
  is shared; lid-closed failover itself needs the lid closed and was not run).
- Unit test fails on old behavior and passes on new — **met for the rule**
  (`testHardwareFormatWinsWhenEngineKeepsStaleAggregateRate`); the old code had no
  such rule to run against, so the failing state is shown by the hardware runs.
- Remote microphone path, lid-closed failover, device picker unchanged —
  **met by existing tests passing**; only the `onInputUnavailable` signature and
  the `.keep` branch of `evaluateInputHealth()` changed there.
- Zero-frame retry then localized error — **met** (pure-logic tests, workflow
  test, hardware runs). The `pipeline.mic_no_audio` key exists in `en` and
  `zh-Hans` (key parity enforced by `ci-basic-checks.sh`).
- Rollback is a revert — **met**, no migration.

## Residual risk

- A Bluetooth headset that takes more than 1.5 s to deliver its first frame gets
  one capture restart, then an error after about 3 s. Not testable here; owner:
  maintainer, observe after release.
- A session released before 1.5 s with zero frames still reports "no speech" (the
  approved scope). The format fix removes the known cause.
- `installTap` raises an Objective-C exception on a format mismatch in some engine
  states and Swift cannot catch it. The first start keeps the previous client-format
  fallback for a device that reports 0 Hz; restarts never use it. A catch layer
  would need an Objective-C target and is out of scope.
- Not exercised: lid-closed failover, a Bluetooth input, a mid-session device
  switch by the user, and an end-to-end hotkey session in the signed app.
- `installTap(onBus:bufferSize:format:block:)` is deprecated in macOS 27; the
  compiler warns. Migration is a non-goal here.

## Decision

Ready for review. All automated checks pass and the root cause is fixed on real
hardware; the end-to-end signed-app hotkey session and the residual risks above
remain for the maintainer. Commit, push, and opening a PR were authorized by the user on 2026-10-26.
Merge, tagging, and release are not authorized by this artifact.
