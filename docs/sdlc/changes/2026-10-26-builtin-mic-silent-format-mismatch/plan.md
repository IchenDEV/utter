# Plan: Capture from the device's hardware format and guard against silent capture

**Status:** approved
**Approved-by:** User, explicit approval in this conversation (answered the approval question: approve)
**Approved-date:** 2026-10-26
**Upstream:** [spec.md](spec.md)

## Work items

Work happens in the worktree `~/.cursor/worktrees/opentype/mic-silent-fix` on
branch `cursor/fix-builtin-mic-silent` (from `origin/main` at v0.0.59). The main
checkout and its uncommitted changes are not touched.

- [x] **Regression tests first.** Add `Tests/UtterAudioTests/CaptureFormatChoiceTests.swift`
  and `CaptureLivenessTests.swift` per the spec's test table and confirm the
  format test fails against the current "use the client format" behavior.
- [x] **Format choice.** Add the pure rule that picks hardware, then client, then
  none, from sample rate and channel count. Add `currentCaptureFormat()` to
  `AudioCaptureManager` that applies it to `inputNode.inputFormat(forBus: 0)` and
  `outputFormat(forBus: 0)` and logs one numeric line when the rates differ.
- [x] **Use it everywhere a format is read.** `startLocal` reads the format once
  after `setInputDevice`, uses it for `AVAudioFile`, and passes it to
  `installCaptureTap(format:)`. `switchInput` does the same.
- [x] **Liveness guardrail.** Add the pure `CaptureLiveness.decide`, the
  `captureStartedAt` / `livenessRetries` state, `restartCapture(on:)` extracted
  from `switchInput`, and the liveness check that runs in `evaluateInputHealth()`
  only when the failover decision is `.keep`.
- [x] **Error reporting.** Add `AudioCaptureStartFailure.noAudioReceived` and the
  `pipeline.mic_no_audio` string in `en` and `zh-Hans`. Change
  `CaptureCallbacks.inputUnavailable` to carry the reason and update
  `CaptureCallbackGate`, `LocalCaptureDriver`, `VoiceSessionJob+Capture`, and the
  two invocations in `VoiceWorkflowTests`. Add a workflow test for the new reason.
- [x] **File-size check.** Keep each touched file under 300 lines; split a new
  extension file if `AudioCaptureManager+Devices.swift` grows past that.
- [x] **Verification record.** Write `verification.md` with commands, exit codes,
  runtime evidence, and residual risk, then set it to `pending approval`.

### Implementation notes (refinements within the approved spec)

- `Sources/UtterAudio` keeps platform-neutral code outside `Native/` (the target
  excludes `Native/` on other platforms). So the format rule is implemented as a
  pure function over sample rate and channel count that returns
  `hardware | client | none`, in `Sources/UtterAudio/CaptureFormatChoice.swift`,
  and the `AVAudioFormat` selection is a small glue step in `Native/`. Behavior
  and tests match spec section 1; only the type shape and file placement differ
  from the sketch. `CaptureLiveness.swift` is Foundation-only and stays outside
  `Native/` as specified.
- Found during real-hardware verification: on an engine that already ran,
  `installTap` with a format that disagrees with the hardware raises an
  Objective-C exception that Swift cannot catch. `restartCapture` therefore
  refuses to tap unless the hardware format is usable (`allowClientFallback:
  false`) and reports `noAudioReceived` instead. The first start keeps the previous
  client-format fallback. This narrows the retry path and adds no scope.
- If implementation uncovers a behavior change beyond the spec, stop and record it
  here instead of widening the change.

## Verification plan

- [x] New unit tests pass and the format test is shown failing on the old behavior
  (stash the fix or run it against the pre-change tree) before it passes.
- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test --jobs 4`
- [x] Real-hardware capture check (done through a temporary XCTest driving the real `AudioCaptureManager`; `build-and-run.sh --verify` was not used because it kills the user's running Utter and relaunches a differently signed copy). Debug build via `bash scripts/build-and-run.sh --verify`, then a real hotkey
  recording on the affected MacBook with the built-in microphone, once as the
  system default and once explicitly selected: a transcript is produced and
  `/usr/bin/log show` for the process contains no `Format mismatch` or
  `Failed to create tap`.
- [ ] Manual (not done, left to the maintainer): record with one other available input and switch inputs from the
  picker, confirming each still produces audio.
- [x] `bash scripts/build-app.sh` release-style build (capture runtime changed).
- [x] `git diff --check` and a final diff review.

Limits to record, not to fake: a lid-closed run, a Bluetooth headset profile
switch, and a physical 44.1 kHz versus 48 kHz mismatch on other hardware cannot be
produced in CI; they remain manual or residual risk in `verification.md`.

## Human gates

- Intent approved by the user on 2026-10-26.
- Spec approved by the user on 2026-10-26.
- Plan approved by the user on 2026-10-26 before any source change.
- Verification needs approval before commit and PR.
- Pushing, opening the PR, merging, tagging, and releasing are not authorized by
  this plan and each needs its own request.

## Rollback

Revert the change's commit. No settings or data migration is involved. The
guardrail and the format fix are independent and can be reverted separately.
