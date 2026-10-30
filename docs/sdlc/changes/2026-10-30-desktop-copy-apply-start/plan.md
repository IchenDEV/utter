# Plan: Desktop Copy and Apply-replacement buttons must start a session

**Status:** approved
**Approved-by:** User, answered the approval question in this conversation: approve
**Approved-date:** 2026-10-30
**Upstream:** [spec](spec.md)

## Work items

- [ ] Write the failing tests first and record that they fail on `0e0f3c1`:
  - `Tests/UtterSessionTests/SessionDriverTests.swift`: a recording fake job;
    `.unselected` + `.input` binds `.local`; `.unselected` + `.copy` and
    `.unselected` + `.applyReplacement` start without `bind`.
  - `Tests/OpenTypeTests/` (new file next to the existing host E2E tests, using
    `VoiceWorkflowFixture` and a real `NativeDesktopHost`): `host.copy`,
    whitespace-only `host.copy`, and `host.applyReplacement` (expired and ready
    pending replacement), asserting requests, `deliveryStatus`, history, and the
    recent-output anchor.
- [ ] Change the one condition in `Sources/UtterSession/SessionDriver.swift`
  (`admit`): bind `.local` only when `intent.operation == .input`.
- [ ] Re-run the new tests; they pass. Run the existing driver, replacement,
  restore, and presentation tests.
- [ ] Update this bundle's `verification.md` with command output and results
  (set `pending approval`; the human approves it).

## Verification plan

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] Development build, real window: Settings -> History copy button and
  context menu, menu bar popover copy buttons. For each, `pbpaste` equals the
  shown text, and
  `log show --last 5m --predicate 'subsystem == "com.opentype.voiceinput"'`
  has no `Desktop action could not start`.
- [ ] Release-style build is not required: no packaging, dependency, or runtime
  resource change.

## Human gates

- Approval of this spec and plan (given together by the user's earlier decision).
- Running `bash scripts/build-and-run.sh` stops (`pkill -x Utter`) and replaces
  the user's running Utter with a development build. Ask before running it, and
  say that the installed Utter must be relaunched afterwards.
- Approval of `verification.md`, the PR, merging, and any release.
