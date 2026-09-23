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
| Incident-stage provenance | Read-only local history | Four processed menu-bar records on 2026-09-21/23 UTC had 357-character `rawText` beginning `Terms: ` and 351-character `processedText` without that prefix. The literal prefix and ordered vocabulary match the legacy Qwen context construction. No private dictionary contents or audio were copied into the repository. |
| Separate learned-dictionary substitution | Read-only local history and dictionary | Three older records had “嗯。” as ASR text and “Do anything” as processed text. An active learned `嗯。 -> Do anything` rule deterministically explains the change; it became active after two correction observations. The original edit records have been pruned, so user intent cannot be inferred. |
| `TranscriptionSanitizerTests` | Pass | Ordered vocabulary echo rejected; short terms and strong deliberate dictation retained. |
| `VoicePipelineSilentInsertionTests` | Pass | Direct, processed, instant insert, command, and translation paths made zero insertion calls for rejected audio. |
| `IntegrationOutputTests/testCoordinatorRejectsWeakAudioVocabularyEcho` | Pass | Live integration's shared transcript preparation rejected the list. |
| `SpeechActivityClassifierTests` | Pass | Generated white noise and tones at three amplitudes rejected; repository English/Chinese speech, 0.8-second clips, padded 0.25-second clips, and 10%-volume short clips accepted; missing, empty, and cancelled audio rejected. |
| Local Qwen noise replay | Pass | `OPENTYPE_QWEN_NATIVE_INTEGRATION=1` test with installed model rejected generated non-speech noise after independent speech classification. |
| Qwen prompt-echo regression | Pass | The same installed-model noise replay now asserts that ASR output does not begin with `Terms: ` even when a technology recognition context was configured on the engine. |
| Local Qwen repository speech samples | Pass | Installed model transcribed English and Chinese repository samples without downloading weights. |
| Formatting-output guard | Pass | `TranscriptFidelityGuardTests` rejects a list copied from formatting prompt terms and an unsupported short-ASR expansion under both fidelity policies. The short historical output came from a learned replacement before formatting, so this guard test does not reproduce that incident. |
| `swift test --scratch-path /tmp/utter-silent-insertion-build` | Pass | 754 XCTest cases, 15 skipped, no failures; one Swift Testing case passed before the later formatting-AI regression test was added. That focused new test passed separately. Scratch path used because a fresh MLX submodule checkout stalled. |
| `bash scripts/sdlc-checks.sh` | Pass | Stage artifacts valid after the user confirmed updated verification. |
| `bash scripts/ci-basic-checks.sh` | Pass | SDLC, localization, resources, lexicon evaluation, and repository checks passed. |
| `bash scripts/build-app.sh --app-only --sign=-` | Pass | Xcode Release build, Metal shader bundle, CLI helper, bundle assembly, ad-hoc codesign, and artifact verification passed. No usable Utter signing identity was installed; this is a local build, not a trusted release. |
| Rebase onto `origin/main` | Pass | Commit `686becb` is based on `60e7ed4` (Confucius4-R2T2 support). Qwen's new `modelID` and tail-padding path remain intact; vocabulary context injection remains removed. |
| Post-rebase checks | Pass | `bash scripts/ci-basic-checks.sh`; `swift test --scratch-path /tmp/utter-silent-insertion-build` (763 XCTest cases, 17 skipped, no failures; one Swift Testing case passed); release-style ad-hoc app build and artifact verification. |
| Real microphone/window check | Not run | Two other Utter instances are active on this Mac. Launching a third copy would conflict with hotkeys and would not provide reliable input-path evidence. |
| Independent verification | Pending | — |

## Acceptance criteria

- The reported vocabulary echo is rejected before insertion, clipboard, edit-command, and history paths — automated menu-bar and integration tests pass; independent review pending.
- Generated non-speech audio is rejected by an independent classifier even when Qwen emits text — local model replay passes; real microphone check pending.
- Clear English/Chinese speech and short clips remain accepted — automated file fixtures pass, including quieter short clips; real microphone check pending.

## Residual risk

- The built-in classifier cannot identify who spoke. Nearby human speech may still be transcribed; this is outside the no-speech and non-speech-noise acceptance criterion.
- The long-list generating stage is strongly identified as Qwen ASR context echo by the saved `rawText` and legacy `Terms: ` construction. The exact incident audio and runtime prompt snapshot were not retained, so the sound that crossed the original RMS gate is unknown. Separate historical records show an active learned rule replacing a short filler utterance. The current branch does not yet prevent that rule from applying to genuine speech. Command mode has a different output contract; the new audio gate remains the primary protection for no-speech recordings.
- The 0.6 speech-confidence threshold is calibrated against the listed fixtures, not a diverse microphone corpus. Real microphone validation and independent review remain required.
- Two other Utter instances prevent a trustworthy real-window test of this local build without interrupting the user's running apps.
- The branch includes `origin/main` at `60e7ed4`; compare against the live PR base again before review or merge, since main can advance.
- Full release signing, GitHub CI, and production behavior have not been verified.

## Decision

The user confirmed the updated verification on 2026-09-24 with the listed evidence gaps visible. Independent high-risk review remains pending. Do not release until a conflict-free PR, signed build, and protected production approval are complete.
