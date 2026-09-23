# Plan: Prevent unsolicited Qwen vocabulary insertion

**Status:** approved
**Approved-by:** User (conversation; revised plan)
**Approved-date:** 2026-09-23
**Upstream:** [spec.md](spec.md)

The user approved an earlier plan on 2026-09-23. Generated non-speech noise produced an insertable Qwen transcript, invalidating that plan. The revised spec has been approved; this updated plan requires its own approval before implementation resumes.

## Work items

- [x] Establish a red regression at transcript preparation: the original sanitizer passed the user's 351-character list on weak audio. Add a safe pipeline insertion spy and green cases for intended speech.
- [x] Replay generated non-speech noise through the installed Qwen model. It returned an insertable “嗯。” rather than the reported list; retain the deterministic vocabulary-echo regression and the new noise regression as separate contracts.
- [ ] Add one recorded-audio speech classifier using the macOS Sound Analysis built-in model. Run it after the RMS gate and before an ASR transcript can reach output in the menu-bar and live integration paths. Use a 0.5-second analysis window, calibrate the acceptance threshold on the listed fixtures, and pad very short recordings in a temporary copy so they receive a classification result. Treat missing files, no results, classifier errors, and cancellation as no speech; clean up temporary copies on every path.
- [x] Remove Qwen's free-text recognition-context injection in `Sources/Speech/QwenNativeASREngine.swift`; retain existing personal and industry replacement behavior after ASR. Delete obsolete context-only code and tests.
- [x] Add a narrow ordered-vocabulary-echo decision to `Sources/Processing/TranscriptionSanitizer.swift` and feed it the session vocabulary at both `VoicePipeline` and `InputSessionCoordinator`. Keep rejection before edit commands, instant insert, formatting, history, and clipboard effects; targeted tests pass.
- [ ] Add fault-injection tests for weak audio and fabricated ASR output; verify every reachable output mode rejects before insertion, clipboard, edit-command, or history side effects. Test classifier success, failure, no-window, and cancellation paths. Probe louder ambient sound and real microphone noise; if non-speech bypasses the gate, revise the design rather than claiming the broad no-speech criterion passed. Test clear intentionally spoken vocabulary, short phrases, and protected dictionary replacements.
- [ ] Review the complete diff for duplicate guards, stale Qwen context paths, privacy-sensitive logs, and changed contracts. Keep each touched Swift file under 300 lines or split at a real responsibility boundary.
- [ ] Prepare `verification.md` with command results, synthetic Qwen replay, affected permission/privacy paths, remaining limits, and rollback. Obtain independent high-risk verification and PR approval before release.

## Verification plan

- [ ] Focused red/green tests: `swift test --filter TranscriptionSanitizerTests`, Qwen engine tests, and pipeline/integration output tests.
- [ ] Real Qwen and Sound Analysis replay: generated silence, the existing two-second noise fixture that produced “嗯。”, several louder/noisier synthetic fixtures, English and Chinese sample speech, 0.8-second speech clips, and padded sub-window speech clips. Keep only generated or repository-owned audio fixtures.
- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] `bash scripts/build-app.sh` for a release-style app build with bundled Metal shaders.
- [ ] Real-window check of no-speech handling and intentional dictation, including local computer microphone and relevant output modes; repeat with remote microphone only if available.
- [ ] Verify the PR branch has no merge conflicts and distinguish local results from GitHub CI, signed release, and production observation.

## Human gates

- The user must approve this plan before implementation begins, as required by `docs/sdlc/README.md`.
- An independent verifier and PR reviewer must approve the high-risk privacy-sensitive change. A protected production release requires its separate human approval.
