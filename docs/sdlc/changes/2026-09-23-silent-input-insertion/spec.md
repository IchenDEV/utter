# Spec: Prevent unsolicited Qwen vocabulary insertion

**Status:** approved
**Approved-by:** User (conversation; confirmed the three-part redesign)
**Approved-date:** 2026-09-24
**Upstream:** [intent.md](intent.md)

The user rejected the earlier design after it disabled Qwen recognition hints and left a harmful learned rule active, then confirmed a three-part redesign on 2026-09-24. The earlier implementation and verification remain historical evidence, not acceptance of this revision.

## Context

The user identified the local Qwen recognition model and computer microphone. Real-time recognition and overlay behavior remain unknown. The reported output starts with terms present in the user's personal dictionary and continues with the bundled technology lexicon in its source order. In the incident-era implementation, `VoicePipeline` combined those terms into `SpeechRecognitionContext`, and `QwenNativeASREngine` passed the resulting `Terms: ...` string into `Qwen3ASRModel.generate(context:)`. The current draft PR has removed that context. RMS loudness does not distinguish speech from other sound. The final transcript passes through `TranscriptionSanitizer.prepare` and may reach direct or processed insertion, including instant insert.

The user clarified that no words were spoken and questioned whether the later formatting AI added the list. Local `input_history.json` retains both stages. Four processed menu-bar records (2026-09-21 and 2026-09-23 UTC) show the long list already present in `rawText`, beginning with the literal `Terms: ` prefix; `processedText` removes that prefix and changes only a few terms and punctuation. The old `SpeechRecognitionContext.contextualPrompt()` generated precisely a `Terms: ` vocabulary prompt, which `QwenNativeASREngine` passed to `Qwen3ASRModel.generate(context:)`. This strongly identifies Qwen's echo of its recognition context as the long-list source. The original audio and exact runtime context snapshot were not retained, so the triggering sound and exact prompt bytes cannot be replayed. The overlay state is also unknown.

Three older processed records show a separate failure: the two-character ASR result “嗯。” became “Do anything”. Read-only inspection of the local personal dictionary found an active learned `嗯。 -> Do anything` rule with confidence 0.82 and two evidence records. `PersonalDictionarySnapshot.applyReplacements` runs before formatting and deterministically makes this substitution. The previous attribution to the formatting AI was wrong. The rule was created by correction capture and activated after two observations; the original edits were pruned from the 500-record history, so their intent is unknown. A no-speech gate blocks a non-speech source, but the learned-rule eligibility and scope also need review before the dictionary is considered safe.

Before the first patch, the sanitizer only rejected the isolated phrase “Do anything” on weak audio. A temporary command that compiled that sanitizer with a minimal audio-activity stub and supplied the user's reported list returned `FAIL: passed through 351 characters` (exit 1). This reproduced the transcript-preparation gap, not the complete microphone-to-Qwen incident. No private microphone recording or dictionary contents were copied into the repository.

After the first implementation, a local Qwen replay with generated non-speech noise passed the RMS gate and returned “嗯。”; `TranscriptionSanitizer.prepare` accepted it. The first design therefore cannot satisfy the no-speech criterion. A separate read-only prototype of Apple's built-in Sound Analysis classifier gave maximum `speech` confidence 0.357 for that two-second noise clip, 0.91–0.97 for the repository's English and Chinese speech samples, and 0.91–0.94 for 0.8-second speech clips using 0.5-second analysis windows. A 0.25-second speech crop padded to 0.75 seconds scored 0.63–0.65. These are feasibility results, not a calibrated acceptance threshold.

## Superseding design

The four saved sessions already contain the ordered `Terms: ...` list in Qwen's raw transcript. Formatting changed only its presentation. The original audio and exact runtime prompt are unavailable. Separate saved sessions show raw `嗯。` becoming `Do anything` because of an active learned dictionary rule, before formatting. Its source edits were pruned, so there is no evidence that it was an intended reusable correction. A synthetic rare-name sample was recognized correctly with a one-term Qwen hint and incorrectly without it; this is a narrow benefit to preserve, not a measured production success rate.

1. **One recorded-audio speech decision.** Menu-bar capture, live integration capture, and integration audio-file import must call the same classifier before any final transcript or output is committed. Keep RMS as a cheap early filter where available. Missing/unreadable audio, no classification window, cancellation, or classifier failure produces no output and a recoverable status. Streaming partials remain provisional.
2. **Bounded Qwen recognition hints.** Restore Qwen context using only effective personal-dictionary replacement terms for the current target app and selected language. Prefer manual entries, then recent/high-evidence learned entries; deduplicate and impose a small phrase-count and character budget. Do not include the full dictionary, bundled industry lexicon, edit rules, or whole correction pairs. Preserve post-ASR personal and industry correction. Other recognizers keep their established mechanism but receive effective scoped personal entries.
3. **Pre-output prompt-echo handling.** Compare Qwen's candidate with the exact context supplied to that recognition call. On a prompt-prefix or ordered-term echo, discard it and retry the same audio once with empty context. Revalidate the retry at the shared transcript boundary. If it still echoes, lacks speech evidence, or errors, finish without insertion, clipboard, command, or history. Short deliberately spoken terms and ordinary sentences remain eligible.
4. **Safe learned corrections.** Enforce learned-entry app/language scope at the dictionary snapshot used by recognition, replacement, formatter hints, and protected terms. A scoped learned entry is ineligible when the required context is unknown; unscoped manual entries stay global. Reject automatic learning from a short filler/interjection or non-speech artifact, including the observed `嗯。` source. Apply the same eligibility to persisted learned entries so the existing unsafe rule cannot act. Do not silently delete or rewrite the local dictionary. Do not merge evidence from different app/language scopes into a global rule. User-entered manual corrections remain possible.

Recorded audio is the source for speech evidence, the session snapshot is the source for effective terms, and final transcript acceptance is the transaction boundary before external effects. Replace the narrow coordinator seam if it cannot carry exact context and scope; do not add three unrelated path guards.

## Failure modes and limits

- The classifier can reject quiet speech or accept humanlike ambient sound. Calibrate with short English/Chinese speech, quiet speech, silence, and several noise types; verify the computer microphone. Nearby human speech is outside this no-speech guarantee.
- A small Qwen prompt can still echo. One empty-context retry contains detected echoes but costs an extra inference. Rare names outside the term budget may be less accurate; measure the tradeoff.
- Scope filtering may leave a learned correction unavailable when app or language is unknown. Prefer a missed correction to an unintended replacement. Manual global entries remain available.
- Do not log audio, transcript contents, or dictionary terms. Preserve existing user data. Roll back to the prior signed artifact if necessary; do not restore the full Qwen term list without separate review.

## Acceptance and verification

- A deterministic regression reaches all three recorded-audio paths with non-speech audio and fabricated vocabulary output and observes no final text, clipboard, command, or history side effect.
- Local Qwen replay shows a bounded relevant term helps a rare-word sample, and prompt echo triggers at most one empty-context retry that cannot insert the list. Deliberately spoken short terms and ordinary speech remain eligible.
- A regression proves `嗯。 -> Do anything` cannot arise from automatic learning or an existing learned rule, while a manual correction and valid scoped learned correction work in their proper app/language.
- Fault injection covers classifier errors, cancellation, missing audio, retry failure, and unknown scope. Run repository checks, full tests, release-style build, real-window microphone QA, independent high-risk review, conflict-free PR review, and separate protected release gate.
