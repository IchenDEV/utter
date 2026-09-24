# Verification: Prevent unsolicited Qwen vocabulary insertion

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

The prior verification was approved for the superseded design. Results below describe the existing draft PR and do not establish acceptance of the revised design approved on 2026-09-24. Fresh verification is required after implementation.

## Revised-design evidence (2026-09-24, pending independent review)

| Check | Result | Evidence |
|---|---|---|
| Session dictionary scope | Pass locally | Snapshots filter learned entries by app and language; menu-bar and integration admission capture one effective snapshot. Global manual entries remain available. Tests cover unknown context, cross-app evidence, and valid scoped replacements. |
| Unsafe existing learned rule | Pass locally | The saved-type `嗯。 -> Do anything` rule is inert on use and shown as pending when loaded, without rewriting the dictionary file. A user approval or edit explicitly converts it to a manual rule. New correction capture rejects the filler source. |
| Qwen context | Pass locally | Qwen receives at most eight effective personal replacement terms within a 160-character terms budget; the expanded industry lexicon remains available for post-ASR correction without being sent whole to Qwen. Tests cover budget and deduplication. |
| Qwen echo recovery | Pass locally | A prompt-prefix or ordered-term echo triggers one empty-context retry. A repeated echo produces no transcript; a retry error cannot return the first echo. Short spoken terms remain eligible. |
| All recorded-audio entry paths | Pass locally | Menu-bar, live integration, and imported audio call the same Sound Analysis classifier before final transcript and output. Imported-audio regression asserts no ASR call or final session when the classifier rejects. |
| Existing session lifecycle | Pass locally | Integrated current `main` ownership/cancellation changes without removing their transaction guard. Ten ownership tests and the mode-specific insertion tests pass. |
| Full `swift test --scratch-path /tmp/utter-silent-insertion-build` | Pass locally | 793 XCTest cases, 18 skipped, zero failures; one Swift Testing case passed. Ran after integration with current `main`. |
| `bash scripts/sdlc-checks.sh` and `bash scripts/ci-basic-checks.sh` | Pass locally | Both completed after the merge resolution. |
| Installed local Qwen replay | Pass locally | Generated noise was rejected; repository-owned English and Chinese speech samples were transcribed. The synthetic rare name was rendered as “Zerolith” without a hint and “Zyralith” with one or three bounded hints. This is one generated voice sample, not a general accuracy estimate. |
| Release-style app build | Pass locally | `bash scripts/build-app.sh --app-only --sign=-` built the app and CLI helper, bundled Metal resources, and passed artifact verification. Ad-hoc signing is for local checking only. |
| PR mergeability and remote CI | Pass at observed head | GitHub reported draft PR #112 `MERGEABLE` at `9f9ccc8`; Contract & Tests, Release-style App Build, and SDLC Gate all succeeded. |
| Real computer-microphone silence QA | Pass for live integration route | Temporarily stopped both original instances, launched the ad-hoc local build, granted its microphone permission through the onboarding UI, and recorded three seconds from the default MacBook Pro Microphone. The live recording API returned `no_speech_detected` with no transcript or final text. |
| Real computer-microphone speech QA | Inconclusive | Two attempts to play a Chinese technical sentence through the MacBook speakers into the microphone returned `no_speech_detected`; the system output was subsequently observed muted. No valid audible speech sample was confirmed at the microphone. The menu-bar hotkey path was not exercised because this ad-hoc build lacked Accessibility authorization. |
| Original app restoration | Pass | Stopped the test build and restarted the two exact original bundles, one from `/Applications/Utter.app` and one from the prior worktree. Restored `hasCompletedOnboarding=true` and `activationMode=longPress`; both original processes were observed running. The speaker mute state was left as the user set it. |
| Independent verification, signed release, production observation | Pending | The author cannot satisfy the independent high-risk review or protected production gate. |

These results verify the revised local implementation only. The exact incident audio was not retained, and Sound Analysis cannot determine who spoke. The draft PR stays unreleased until the remaining gates are met.

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
| Real microphone/window check | Partial | The revised-design table above records the new three-second silence result, inconclusive speaker playback, and restoration of both original instances. This older evidence table describes the superseded design. |
| Independent verification | Pending | — |

## Acceptance criteria

- The reported vocabulary echo is rejected before insertion, clipboard, edit-command, and history paths — automated menu-bar and integration tests pass; independent review pending.
- Generated non-speech audio is rejected by an independent classifier even when Qwen emits text — local model replay passes; a three-second real-microphone silence session was also rejected. This does not isolate which of the RMS gate and classifier rejected that session.
- Clear English/Chinese speech and short clips remain accepted — automated file fixtures pass, including quieter short clips; real microphone speech acceptance remains pending.

## Residual risk

- The built-in classifier cannot identify who spoke. Nearby human speech may still be transcribed; this is outside the no-speech and non-speech-noise acceptance criterion.
- The long-list generating stage is strongly identified as Qwen ASR context echo by the saved `rawText` and legacy `Terms: ` construction. The exact incident audio and runtime prompt snapshot were not retained, so the sound that crossed the original RMS gate is unknown. The separately observed learned `嗯。 -> Do anything` rule is now inert unless manually approved or edited.
- The 0.6 speech-confidence threshold is calibrated against fixtures, not a diverse microphone corpus. A real-microphone silence session passed, but an audible speech acceptance test and independent review remain required.
- The two original Utter instances were restored after the test. The ad-hoc test build lacked Accessibility authorization, so menu-bar hotkey insertion was not verified with real audio.
- The branch includes `origin/main` at `7139f54`; compare against the live PR base again before review or merge, since main can advance.
- Remote PR CI passed at `9f9ccc8`; trusted release signing and production behavior have not been verified.

## Decision

The user confirmed this historical verification on 2026-09-24, then rejected the design because Qwen vocabulary help was lost and the unsafe learned rule remained active. It no longer approves the change. Independent high-risk review and fresh verification remain pending. Do not release until a conflict-free PR, signed build, and protected production approval are complete.
