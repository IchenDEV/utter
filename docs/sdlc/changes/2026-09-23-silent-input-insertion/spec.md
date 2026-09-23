# Spec: Prevent unsolicited Qwen vocabulary insertion

**Status:** approved
**Approved-by:** User (conversation; revised design)
**Approved-date:** 2026-09-23
**Upstream:** [intent.md](intent.md)

The user approved the earlier design on 2026-09-23. A real Qwen counterexample invalidated it; the user then approved this revised design on 2026-09-23.

## Context

The user identified the local Qwen recognition model and computer microphone. Real-time recognition and overlay behavior remain unknown. The reported output starts with terms present in the user's personal dictionary and continues with the bundled technology lexicon in its source order. At recording start, `VoicePipeline` combines those terms into `SpeechRecognitionContext`. `QwenNativeASREngine` passes the resulting `Terms: ...` string into `Qwen3ASRModel.generate(context:)`. The recording gate uses RMS loudness, which does not distinguish speech from other sound. The final transcript then passes through `TranscriptionSanitizer.prepare` and may reach direct or processed insertion, including instant insert.

The user clarified that no words were spoken and questioned whether the later formatting AI added the list. Local `input_history.json` retains both stages. Four processed menu-bar records (2026-09-21 and 2026-09-23 UTC) show the long list already present in `rawText`, beginning with the literal `Terms: ` prefix; `processedText` removes that prefix and changes only a few terms and punctuation. The old `SpeechRecognitionContext.contextualPrompt()` generated precisely a `Terms: ` vocabulary prompt, which `QwenNativeASREngine` passed to `Qwen3ASRModel.generate(context:)`. This strongly identifies Qwen's echo of its recognition context as the long-list source. The original audio and exact runtime context snapshot were not retained, so the triggering sound and exact prompt bytes cannot be replayed. The overlay state is also unknown.

Three older processed records show a separate failure: the two-character ASR result “嗯。” became “Do anything”. Read-only inspection of the local personal dictionary found an active learned `嗯。 -> Do anything` rule with confidence 0.82 and two evidence records. `PersonalDictionarySnapshot.applyReplacements` runs before formatting and deterministically makes this substitution. The previous attribution to the formatting AI was wrong. The rule was created by correction capture and activated after two observations; the original edits were pruned from the 500-record history, so their intent is unknown. A no-speech gate blocks a non-speech source, but the learned-rule eligibility and scope also need review before the dictionary is considered safe.

The existing sanitizer only rejects the isolated phrase “Do anything” on weak audio. A temporary command that compiled the real sanitizer with a minimal audio-activity stub and supplied the user's reported list returned `FAIL: passed through 351 characters` (exit 1). This reproduces the transcript-preparation gap, not the complete microphone-to-Qwen incident. No private microphone recording or dictionary contents were copied into the repository.

After the first implementation, a local Qwen replay with generated non-speech noise passed the RMS gate and returned “嗯。”; `TranscriptionSanitizer.prepare` accepted it. The first design therefore cannot satisfy the no-speech criterion. A separate read-only prototype of Apple's built-in Sound Analysis classifier gave maximum `speech` confidence 0.357 for that two-second noise clip, 0.91–0.97 for the repository's English and Chinese speech samples, and 0.91–0.94 for 0.8-second speech clips using 0.5-second analysis windows. A 0.25-second speech crop padded to 0.75 seconds scored 0.63–0.65. These are feasibility results, not a calibrated acceptance threshold.

## Design

1. **Require independent speech evidence before ASR output can be committed.** Use the macOS built-in Sound Analysis classifier on the recorded audio file, with a short supported analysis window. Reject when no speech window reaches a threshold calibrated on generated noise, repository speech samples, short utterances, and real microphone captures. For recordings shorter than the classifier window, analyze a temporary padded copy so short spoken words are not automatically rejected. A classifier error or unavailable file fails closed with no insertion and a clear status; numeric confidence may be logged only in debug builds.
2. **Remove free-text vocabulary priming from Qwen ASR.** Qwen receives an empty recognition context. Keep personal-dictionary and industry-lexicon corrections after ASR, so existing text cleanup still applies. Other recognizers retain their existing vocabulary mechanisms unless a replay shows the same failure there.
3. **Add a shared prompt-echo rejection at transcript preparation.** Pass the session's effective vocabulary snapshot into the common preparation boundary used by menu-bar voice input and integrations. Reject a transcript when it substantially reproduces a long ordered run of that supplied vocabulary and audio evidence is weak. Do not reject a single matching term or a short ordinary sentence. The policy operates before spoken-edit resolution, formatting, clipboard writes, history, and instant insert.
4. **Keep the RMS gate as a cheap first filter.** Its readings remain useful for absolute silence but cannot alone prove speech. Do not simply raise its global threshold: that would discard quiet speech without reliably excluding ambient noise.

The module boundary is one recorded-audio speech decision, the ASR context supplied to Qwen, and the shared transcript-preparation decision. The recorded audio is the source of truth for speech; the vocabulary list is a recognition hint, never content to insert. The final transcript decision is the transaction boundary before externally visible output. No second insertion pipeline or model-specific output blacklist is introduced.

Compared with repeatedly adding phrases to `weakAudioWholeTranscriptHallucinations`, this design addresses the source and the common gate. Replacing the whole speech module or app would multiply model, permission, migration, and validation work without evidence of broader architectural failure.

## Safety and failure modes

- **False rejection:** A user may deliberately read a long vocabulary list aloud. Reject only when weak audio evidence accompanies a strong ordered echo; test clear speech and short technical phrases. The Qwen context removal may reduce recognition of rare names; post-ASR replacements continue, and this tradeoff must be checked with speech fixtures.
- **False acceptance:** Sound classification is probabilistic. An unrelated Qwen hallucination or humanlike background sound might still pass. Calibrate and test with multiple noise and speech fixtures, plus the actual microphone. Do not claim universal prevention from the current small prototype.
- **Classifier failure:** A missing or unreadable file, no results, cancellation, or analysis error must not permit an ASR transcript to reach output. Preserve a recoverable user-facing status and do not retain an extra audio copy.
- **Privacy:** Do not persist captured audio or user dictionary contents in fixtures or diagnostics. A rejected transcript must cause no input insertion, clipboard write, edit command, or history entry.
- **Compatibility:** Keep the public `SpeechEngine` behavior and non-Qwen recognition paths stable unless the shared gate requires a narrow signature change. Preserve remote microphone and integration behavior with contract tests.

## Test strategy

- First write a failing regression test for the reported ordered vocabulary echo at the shared transcript-preparation seam, including a simulated weak recording that passes the RMS gate. Assert no downstream insertion or clipboard call through the pipeline's test seam.
- Turn the generated-noise Qwen replay that returned “嗯。” into a green regression by gating on independent speech evidence, not by blacklisting that valid utterance. Test English, Chinese, 0.8-second clips, and padded sub-window clips; measure false acceptance and rejection at the chosen threshold.
- Test single technical terms, “Do anything” with clear speech, ordinary mixed-language sentences, and deliberate long-list dictation with strong audio evidence.
- Replay synthetic silence and several non-speech noises through the installed local Qwen model with the technology lexicon enabled; compare the current and proposed context behavior without storing private audio.
- Exercise direct, processed, command, translation, instant-insert, streaming, and integration paths at their shared preparation boundary. Run `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`, a release-style build, and independent verification. Document any runtime path that cannot be exercised.

## Rollout and rollback

Ship behind the existing signed-release and PR approvals. Observe no-speech rejections and legitimate technical dictation with privacy-safe counts only. Stop rollout if clear speech is lost or unsolicited text still inserts. Roll back the release to the previous signed artifact; restore the prior Qwen context behavior only after a new reviewed design addresses prompt echo.
