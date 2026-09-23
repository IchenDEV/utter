# Intent: Unified input-session ownership with all product capabilities preserved

**Status:** approved
**Approved-by:** User (conversation confirmation)
**Approved-date:** 2026-09-24
**Upstream:** User request, 2026-09-23: fix orchestration problems and explain specialized text rules.

## Problem

Utter is a local-first voice input app with optional cloud support. All existing product capabilities must remain available.

Source review identified separate ownership in VoicePipeline, InputSessionCoordinator, and OpenTypeService. Integration recording reserves activeSession only after awaiting engine loading; file processing never reserves it. Cancelling an integration session releases resources without owning/cancelling the full processing task. A late output can write history before service completion rejects its terminal session; release(active) does not verify current identity. These are source-derived concurrency risks, not yet runtime reproductions.

VoicePipeline and SpeechEngineProvider separately own ASR instances and loading policies. TextProcessor is already shared in production and must remain shared. Remote microphone input already routes through VoicePipeline; transport handshake state is not a redundant transcription pipeline.

Specialized strings mix protocol compatibility, model instructions, vocabulary data, and heuristics that accept, reject, or modify user text. Their different purposes and evidence must be made explicit before changing them.

## Outcome

Every input entry point observes consistent session ownership, cancellation and resource cleanup. Obsolete tasks cannot affect a newer input. All engines, local/cloud modes, editing, translation, integration APIs, remote microphone, context and learning features remain supported.

## Scope

Session admission, preparation, recording, processing, cancellation, result/history publication, cleanup and ASR lifecycle reuse across menu bar, remote microphone, HTTP/XPC and audio-file entry points. Audit specialized text rules and identify demonstrated obsolete or duplicated rules; behavior changes require positive and counterexample coverage.

## Constraints

- Preserve public API shapes, permission checks, client ownership and terminal event semantics.
- Preserve all product capabilities and existing stored settings/data.
- No whole-app rewrite, new framework, automatic signing fallback or release.
- UI and API state must reflect execution ownership rather than independently decide whether resources are free.
- Do not delete supported protocol fields, linguistic rules or vocabulary merely because they contain literal text.
- Risk: medium for internal lifecycle/runtime changes; escalate before changes to public compatibility or permission/security boundaries.

## Acceptance criteria

1. Competing entries during a deliberately suspended model load cannot both acquire execution resources.
2. Audio-file preparation and processing participate in the same admission contract as recording.
3. Cancel during preparation prevents later capture; cancel during processing prevents subsequent history/result publication.
4. Cancel followed by a new request is safe: old callbacks, output and cleanup cannot stop, erase or complete the new session. Resources still used by non-cooperative work are not prematurely reused.
5. Repeated stop/cancel and shutdown follow deterministic terminal behavior; unauthorized clients cannot release another session.
6. Each session uses a consistent engine/settings snapshot; changing settings cannot redirect in-flight audio or results.
7. ASR loading has one production ownership path, while preserving model readiness, progress, permission and recovery behavior.
8. Streaming policy differences are explicitly justified or reconciled without silently removing supported behavior.
9. Existing translation, editing, deferred replacement, screen context, learning and all input entry points retain their behavior. At most one result/history commit per session; deferred replacement retains its explicit second-edit contract.
10. Specialized-text review identifies purpose, callers, evidence and preservation counterexamples. Literal dictated JSON, quoted instructions, deliberate repetitions, real closing phrases and meaningful numbers/negations remain protected.
11. Relevant regression tests, repository checks and release-style build pass; actual entry-point verification is recorded separately from unit tests.

## Specialized text findings

| Source | Purpose | Current effect | Review boundary |
|---|---|---|---|
| Sources/Processing/TranscriptionSanitizer.swift | ASR artifact filtering | Weak-audio-only handling of `do anything`, closing phrases such as `感谢观看`, and transcript repetition; explicit silence markers are filtered separately | Real dictated phrases and quoted markers need counterexamples; audio-file path lacks measured audio evidence |
| Sources/Processing/TranscriptFidelityGuard.swift and TranscriptContentFidelity.swift | Reject unsafe model transformations | Language-specific negation/self-correction patterns and overlap/length thresholds can force fallback to source | These rules inspect comparison text; they are not direct filler-word deletion from output |
| Sources/Processing/TranscriptSpokenNumberParsing.swift | Compare spoken/written numbers | Chinese/English number mappings support fidelity checks | Preserve numbers, leading zeros, units and self-correction distinctions |
| Sources/Processing/LLMActionValue.swift and LLMFinalTextOutput.swift | Decode model output variants | Field aliases, nested envelopes and scalar coercions infer actions/final text | Separate supported contracts from speculative variants; preserve literal JSON dictation |
| Sources/Prompts/PromptCatalog+ASRQuality.swift | Model instructions | Multilingual examples guide cleanup, spelling and fidelity | Examples such as Utter/hotkey/API are instructions, not explicit local replacement rules; assess domain bias before editing |
| Sources/Resources/IndustryLexicons.json | Product vocabulary data | Terms, aliases and corrections are user-selectable domain functionality | Keep this requested product feature |
| Sources/Processing/TextProcessor+Output.swift | Historical call-site compatibility | allowsGuardFallback is ignored; fallback always preserves source | Candidate for removal with all callers updated and behavior unchanged |

## Open questions

No product-scope questions: all capabilities remain. The user explicitly confirmed the requested one-change waiver of per-stage stops on 2026-09-24. Design, implementation and verification may proceed continuously; this does not approve deployment or constitute review of unseen artifacts.
