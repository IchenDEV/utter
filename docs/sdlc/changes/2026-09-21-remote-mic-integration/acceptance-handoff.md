# Human acceptance handoff: Xiaomi remote wireless microphone

**Status:** ready for human acceptance; not approved for merge or release
**Artifact source / #104 head at build:** `31b3c7f614656c59855b7fd556734a11543fa9eb`
**Verified product code/test head:** `0998430e3e28215949d1b8d7398c795e4ab47923`
**Head relationship:** `31b3c7f6` is a documentation-only descendant of the verified product head; Sources and Tests are unchanged.
**Verified code/test tree:** Sources `7bf86068d1142fdd2d1c1bae82131997f780356c`; Tests `431612931b709adf60b1f3b8180bc1c22b558418`
**Upstream:** `verification.md`

## Downloadable CI acceptance artifact

The approved fixed-head artifact workflow completed successfully:

- Run: [`35684827747`](https://github.com/IchenDEV/utter/actions/runs/35684827747), conclusion `success`.
- Source SHA built: `31b3c7f614656c59855b7fd556734a11543fa9eb`.
- Workflow definition SHA: `1af61dbc60ef141c53ce73f5f777d984f271d378`.
- Runner: `macos-26-arm64`, macOS 26.6.2; Xcode 26.6 (`17F113`).
- Artifact: [`utter-app-31b3c7f614656c59855b7fd556734a11543fa9eb`](https://github.com/IchenDEV/utter/actions/runs/35684827747/artifacts/10676765582), id `10676765582`, 33,050,656 bytes, expires 2026-10-06.
- GitHub artifact ZIP digest: `sha256:35da580f0a9652603dcab7982cc6b3a798196aa58e019aeb7dce7a5fe5e392ca`.
- Inner app archive: `Utter-31b3c7f614656c59855b7fd556734a11543fa9eb.app.zip`.
- Inner app archive SHA-256: `3a54ea580c2277c5cd3398a8d2912830b56fa3e3cd57c82843bf12b4f8aaf3c9`.
- App main binary SHA-256: `db38a824064371f8438a8afc9631fab4975facbbb4641c5564728e00a9bf1ee8`.
- Retention: 14 days. Download requires GitHub access to the Actions artifact while it is retained.

The successful run checked out the exact source SHA with a clean tree, built the
Release arm64 app and CLI helper, compiled AppIcon, applied ad-hoc hardened-
runtime signing, ran `verify-release-artifact.sh`, archived with `ditto`,
re-extracted the archive, ran release-artifact verification again, and uploaded
the archive, checksum file, and manifest.

The first delivery run
[`35683480777`](https://github.com/IchenDEV/utter/actions/runs/35683480777)
is intentionally preserved as failed evidence. The product build, signing, and
release-artifact verification succeeded, then the workflow passed the `.app`
directory rather than `Contents/Info.plist` to `PlistBuddy` and exited 1.
Workflow-only PR #107 corrected that lookup before the successful run. The
one-time push bootstrap was removed after upload; the default-branch workflow
is manual-dispatch only and remains hard-locked to the source SHA above.

The earlier fixed-head PR verification remains available at
[`35626929279`](https://github.com/IchenDEV/utter/actions/runs/35626929279):
Contract & Tests, Release-style App Build, and SDLC Gate all succeeded. That
earlier run uploaded no product artifact; it is superseded for artifact
delivery by `35684827747`, not erased.

## Earlier Mac mini evidence

The Mac mini foreground build and regression evidence remains valid and
separate from the CI artifact:

- `bash scripts/build-app.sh --app-only`: exit 0, Release arm64 app and CLI
  helper built, AppIcon compiled, ad-hoc hardened-runtime signing and
  `verify-release-artifact.sh` passed.
- Local main binary SHA-256:
  `a0965499a77c35f2dfddb1ad1935b566cecae428cc3513cfc0ffad87d86611ad`.
- Source bundle SHA-256:
  `021ed0088aaf8db0df1f7d6afc452d7c9115b7a00e65bb87cffcfd6d5b8b2651`.
- Mutation script SHA-256:
  `52dcad02bc0fbcea2ced082705b0764c004fa73642f0f59c2500b07879da170c`.

These are provenance records, not substitutes for the downloadable CI
artifact and its own checksums above.

## Licensing decision required

`IchenDEV/remote-mic-app` is GPL-3.0-only while Utter is MIT. Development
review does not determine whether this implementation is independent,
derivative, adequately attributed, or distributable. The CI artifact exists
for acceptance testing; its construction does not settle distribution rights.
Before merge or release, the human licensing owner must record one explicit
decision: accept with rationale and required notices, require attribution or
code changes, require a clean-room rewrite, or reject distribution.

## Real-device acceptance procedure

Record tester, date, macOS version, remote model/firmware, artifact SHA-256, and
app logs. Download the artifact above and first verify both the GitHub artifact
digest and the inner app archive SHA-256.

1. Extract `Utter-31b3c7f614656c59855b7fd556734a11543fa9eb.app.zip`.
   Because the app is ad-hoc signed, clear downloaded quarantine if required
   with `xattr -cr Utter.app`, then launch it.
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

- Downloadable CI artifact and checksums: delivered above.
- Hardware result: pending real-device execution.
- Permission/privacy result: pending real-device execution.
- Licensing decision: pending human determination; artifact construction is not
  distribution approval.
- Resource-risk decision: pending release owner.
- CODEOWNERS/SDLC approval: pending.
- Product merge/release approval: pending; #104 remains open and unmerged.
