# Verification: Xiaomi Remote 2 Pro connection and settings page

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md` (approved 2026-10-07)

## Evidence

Run in a sandboxed agent session with no network and no nested sandbox support,
using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/sdlc-checks.sh` | Pass | `SDLC checks passed.` |
| `bash scripts/ci-basic-checks.sh` | Partial | Every step except the four `scripts/tests/test_*.sh` harness tests passed (they create a temporary git repo, which the sandbox forbids); Info.plist/entitlements/strings lint and en/zh key parity pass |
| `swift build` | Pass | `Build complete!` |
| New and neighbouring unit tests | Pass | `RemoteMicDeviceMatcherTests` (7), `RemoteMicKnownRemoteTests` (6), `RemoteMicCallbackRoutingTests` (7), and the other non-pipeline `RemoteMic*` suites: 0 failures |
| Full `swift test` | Not run to completion | The sandbox aborts the xctest process in unrelated suites (`RemoteMicPipelineIntegrationTests` and `ConfigurationTests` abort with malloc/`String.init(cString:)` fatal errors from CoreAudio/AppKit use). CI runs the full suite |
| Release-style app build | Not run | `xcodebuild` cannot evaluate the package manifest inside the sandbox; the PR's `Release-style App Build` job covers it |
| Host-session tests | Pass | `RemoteMicHostSessionTests` (6): latch once, join without re-latching, stale stop ignored, own stop ends it, voice key still latches, `MIC_EXTEND` bytes |
| Real remote check | Not run | Requires the physical remote |

## Acceptance criteria

- Connected-in-macOS remote found without scanning — `testRemoteAlreadyConnectedInSystemSettingsIsConnectedWithoutScanning`, `testRemoteConnectedAsHIDKeyboardIsFoundByName`.
- Unrelated devices ignored, unfiltered scan used — `testUnrelatedConnectedDevicesFallBackToAnUnfilteredScan`, `testOtherNamesAreRejected`.
- `ARN9` nibble order per attempt; stale read ignored — `testModelNumberSelectsTheNibbleOrderForTheCurrentAttempt`, `testModelNumberFromASupersededAttemptIsIgnored`, `testLowNibbleFirstDecodesTheSwappedByteLikeTheStandardOrder`.
- Candidate filtering — `testAdvertisingTheVoiceServiceMakesAnyNameACandidate`.
- Remote tab text keys exist in both localizations, General no longer holds the controls — `testSettingsTextKeysAreLocalized`, key-parity check.
- Real-window light/dark/narrow-width screenshots of the new tab — not captured (no GUI in the session); pending.

## Residual risk

- Not verified on real hardware: whether this unit reports `ARN9`, and whether
  macOS returns it from `retrieveConnectedPeripherals`. The Remote tab shows the
  model, discovery route, and last recording source so a tester can report them.
- Unverified on hardware: whether the remote streams after a host `MIC_OPEN`
  with no key press, how long it streams before its own timeout, and whether
  `MIC_EXTEND` is honoured. The 3 s silence fallback bounds the failure, and
  the tab's "Last recording" shows which microphone was used.
- The silence fallback with the lid closed ends in the existing no-usable-input
  error, since no other microphone exists.
- `XiaomiRemoteMicBridge.swift` remains far above the 300-line guideline; this
  change adds ~100 lines there and does not split it.
- The licensing question for the earlier remote-mic work is still open.

## Decision

Ready for review pending CI and a real-device pass.
