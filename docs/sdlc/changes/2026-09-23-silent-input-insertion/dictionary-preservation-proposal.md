# Proposed revision: keep Qwen dictionary recognition

This proposal is not yet an approved change to `spec.md` or `plan.md`. The current draft PR removes Qwen's recognition-time vocabulary bias. The user identified this as an unacceptable dictionary regression.

## Observed contract

- `QwenNativeASREngine` currently inherits the protocol's no-op `configureRecognition`, then passes `context: ""` to the model. Qwen cannot use the personal or industry vocabulary to recognize an unfamiliar spoken term.
- Exact personal `original -> replacement` rules and industry correction variants still run after ASR in direct and processed output. Processed formatting also receives dictionary context. These paths cannot recover a term when the ASR output contains no supported source phrase.
- The prior Qwen context used one free-text `Terms: ` list. Local history shows that list in the ASR `rawText` before formatting, confirming the echo failure.
- Live integration recordings use the new speech classifier, but imported audio files currently reach ASR without that gate or audio-activity evidence.

## Revised behavior

1. Require speech classification before ASR in every Qwen input route, including imported integration audio. Missing, invalid, cancelled, or non-speech audio ends without a transcript, insertion, clipboard write, or history entry.
2. Restore the existing bounded Qwen vocabulary context from the session snapshot, preserving personal-term priority and active industry terms. Use one authoritative context snapshot for both model input and echo checks.
3. Reject a Qwen transcript that starts with the context marker `Terms: ` and reproduces a substantial ordered run of supplied terms, regardless of RMS strength. Keep the existing weak-audio ordered-list check for echoes without the marker. Do not reject an ordinary spoken term or a deliberately spoken list lacking the marker.
4. Retain deterministic post-ASR replacements and formatting fidelity checks. The vocabulary is a recognition hint and correction source, never independently insertable content.

## Verification before updating the draft PR

- Red/green tests for imported noise audio, a loud synthetic prompt echo, deliberate strong-audio vocabulary dictation, and every output route's side effects.
- Run the installed local Qwen model on generated/repository-owned speech and noise with the restored context. Compare technical-term recognition against the current context-free branch; report both gains and false insertions.
- Run all repository checks and a release-style build; obtain real computer-microphone and independent high-risk verification before approval to merge.

The current context-free implementation has lower prompt-echo exposure but loses Qwen recognition bias. A two-pass recognizer or a speech-module rewrite adds latency, model calls, migration work, and more failure modes; the narrow shared gate and echo contract address the observed failure while retaining the existing dictionary feature. If testing shows prompt echo without `Terms: ` under speech-like noise, revise the design again rather than broadening the blacklist blindly.
