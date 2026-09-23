# Verification: Prevent unsolicited Qwen vocabulary insertion

**Status:** approved
**Approved-by:** User (conversation; confirmation of updated verification)
**Approved-date:** 2026-09-24
**Upstream:** [plan.md](plan.md)

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Original sanitizer counterexample | Red before change | Weak-audio rehearsal passed the user-reported 351-character vocabulary list unchanged. |
| Qwen synthetic-noise counterexample | Red before speech gate | Installed Qwen model returned an insertable “嗯。” from generated non-speech noise. |
| `TranscriptionSanitizerTests` | Pass | Ordered vocabulary echo rejected; short terms and strong deliberate dictation retained. |
| `VoicePipelineSilentInsertionTests` | Pass | Direct, processed, instant insert, command, and translation paths made zero insertion calls for rejected audio. |
| `IntegrationOutputTests/testCoordinatorRejectsWeakAudioVocabularyEcho` | Pass | Live integration's shared transcript preparation rejected the list. |
| `SpeechActivityClassifierTests` | Pass | Generated white noise and tones at three amplitudes rejected; repository English/Chinese speech, 0.8-second clips, padded 0.25-second clips, and 10%-volume short clips accepted; missing, empty, and cancelled audio rejected. |
| Local Qwen noise replay | Pass | `OPENTYPE_QWEN_NATIVE_INTEGRATION=1` test with installed model rejected generated non-speech noise after independent speech classification. |
| Local Qwen repository speech samples | Pass | Installed model transcribed English and Chinese repository samples without downloading weights. |
| Later formatting-AI vocabulary echo | Pass | `TranscriptFidelityGuardTests` rejects a list copied from formatting prompt terms when the ASR source did not contain those terms, under both faithful-correction and bounded-custom-transformation policies. This is a deterministic guard test, not a replay of the original incident. |
| `swift test --scratch-path /tmp/utter-silent-insertion-build` | Pass | 754 XCTest cases, 15 skipped, no failures; one Swift Testing case passed before the later formatting-AI regression test was added. That focused new test passed separately. Scratch path used because a fresh MLX submodule checkout stalled. |
| `bash scripts/sdlc-checks.sh` | Pass | Stage artifacts valid after the user confirmed updated verification. |
| `bash scripts/ci-basic-checks.sh` | Pass | SDLC, localization, resources, lexicon evaluation, and repository checks passed. |
| `bash scripts/build-app.sh --app-only --sign=-` | Pass | Xcode Release build, Metal shader bundle, CLI helper, bundle assembly, ad-hoc codesign, and artifact verification passed. No usable Utter signing identity was installed; this is a local build, not a trusted release. |
| Real microphone/window check | Not run | Two other Utter instances are active on this Mac. Launching a third copy would conflict with hotkeys and would not provide reliable input-path evidence. |
| Independent verification | Pending | — |

## Acceptance criteria

- The reported vocabulary echo is rejected before insertion, clipboard, edit-command, and history paths — automated menu-bar and integration tests pass; independent review pending.
- Generated non-speech audio is rejected by an independent classifier even when Qwen emits text — local model replay passes; real microphone check pending.
- Clear English/Chinese speech and short clips remain accepted — automated file fixtures pass, including quieter short clips; real microphone check pending.

## Residual risk

- The built-in classifier cannot identify who spoke. Nearby human speech may still be transcribed; this is outside the no-speech and non-speech-noise acceptance criterion.
- The incident's generating stage is unknown. Both Qwen ASR and the later formatting AI previously received the vocabulary list, and no per-stage transcript/output was retained for this incident. The formatting-output guard is exercised by a focused test, but command mode has a different output contract; the new audio gate remains the primary protection for no-speech recordings.
- The 0.6 speech-confidence threshold is calibrated against the listed fixtures, not a diverse microphone corpus. Real microphone validation and independent review remain required.
- Two other Utter instances prevent a trustworthy real-window test of this local build without interrupting the user's running apps.
- `origin/main` advanced after this worktree branched and changed Qwen files. Resolve those overlapping changes and confirm the future PR is conflict-free before opening it.
- Full release signing, GitHub CI, and production behavior have not been verified.

## Decision

The user confirmed the updated verification on 2026-09-24 with the listed evidence gaps visible. Independent high-risk review remains pending. Do not release until a conflict-free PR, signed build, and protected production approval are complete.
