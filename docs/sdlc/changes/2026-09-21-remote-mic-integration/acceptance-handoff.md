# Human acceptance handoff: Xiaomi remote wireless microphone

**Status:** ready for human acceptance; not approved for merge or release
**Verified code/test head:** `0998430e3e28215949d1b8d7398c795e4ab47923`
**Verified code/test tree:** Sources `7bf86068d1142fdd2d1c1bae82131997f780356c`; Tests `431612931b709adf60b1f3b8180bc1c22b558418`
**Upstream:** `verification.md`

## CI and artifact handoff

The fixed verification head ran GitHub Actions workflow `PR`, run
[`35626929279`](https://github.com/IchenDEV/utter/actions/runs/35626929279):

- [`Contract & Tests`](https://github.com/IchenDEV/utter/actions/runs/35626929279/job/106423454693): success.
- [`Release-style App Build`](https://github.com/IchenDEV/utter/actions/runs/35626929279/job/106423455071): success.
- [`SDLC Gate`](https://github.com/IchenDEV/utter/actions/runs/35626929279/job/106426889825): success.

There is **no downloadable CI product artifact** for this run. The GitHub
Actions artifacts API reports `total_count: 0`, and `.github/workflows/pr.yml`
builds and verifies `Utter.app` without an `actions/upload-artifact` step.
Consequently there is no artifact download URL, archive digest, or CI-produced
application checksum to hand to the human tester. Run logs remain available at
the links above, but logs are not a distributable app artifact.

The Mac mini foreground build is evidence, not a CI download. It recorded:

- `bash scripts/build-app.sh --app-only`: exit 0, Release arm64 app and CLI
  helper built, AppIcon compiled, ad-hoc hardened-runtime signing and
  `verify-release-artifact.sh` passed.
- Local main binary SHA-256:
  `a0965499a77c35f2dfddb1ad1935b566cecae428cc3513cfc0ffad87d86611ad`.
- Source bundle SHA-256:
  `021ed0088aaf8db0df1f7d6afc452d7c9115b7a00e65bb87cffcfd6d5b8b2651`.
- Mutation script SHA-256:
  `52dcad02bc0fbcea2ced082705b0764c004fa73642f0f59c2500b07879da170c`.

The local binary was not attached, so its checksum cannot be independently
recomputed from this handoff. Release approval must either add an artifact
upload to an approved workflow or have the release owner build the fixed
code/test head and publish the resulting artifact plus its SHA-256.

## Licensing decision required

`IchenDEV/remote-mic-app` is GPL-3.0-only while Utter is MIT. Development review
does not determine whether this implementation is independent, derivative,
adequately attributed, or distributable. Before merge or release, the human
licensing owner must record one explicit decision: accept with rationale and
required notices, require attribution or code changes, require a clean-room
rewrite, or reject distribution.

## Real-device acceptance procedure

Use an artifact produced from the verified code/test head (or a documentation-
only descendant with identical Sources and Tests trees), then record tester,
date, macOS version, remote model/firmware, artifact SHA-256, and app logs.

1. Build and launch with `bash scripts/build-and-run.sh --verify`, or install the
   approved artifact after verifying its SHA-256.
2. Pair the Xiaomi Bluetooth Remote 2 Pro in System Settings → Bluetooth.
3. In Utter Settings → General, enable “Xiaomi remote wireless mic”; accept the
   Bluetooth permission and confirm the state reaches connected.
4. Hold the remote voice key and speak. Confirm Utter starts recording, the
   level/activity indicators respond, and text is inserted.
5. Release the key. Confirm recording stops once and the final spoken audio is
   not clipped or discarded.
6. Disable the feature during an active or starting session. Confirm recording
   terminates and the UI returns to the expected idle state.
7. Disconnect the remote while starting and while recording. Confirm no late
   callback restarts or tears down a replacement session, and the state returns
   to scanning/retrying.
8. Reconnect the same remote and repeat a complete press/speak/release session.
9. With the feature disabled, and with it enabled but no remote ready, confirm
   the existing system microphone fallback still records normally.
10. Preserve the app log, screenshots of permission/connected/recording/idle
    states, and one non-sensitive WAV inspection confirming 16 kHz mono input.

## Acceptance record

- Hardware result: pending.
- Permission/privacy result: pending.
- Licensing decision: pending human determination.
- Downloadable CI artifact and digest: missing; see the CI gap above.
- CODEOWNERS/SDLC approval: pending.
- Merge/release approval: pending.
