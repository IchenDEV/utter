# Design: Input execution ownership

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** intent.md

## Authorization

The user confirmed the explicit one-change waiver of per-stage stops on 2026-09-24. This artifact records the resulting design; it is not represented as independently human-reviewed.

## Boundary and alternatives

| Approach | Implementation and migration | Verification and operation | Long-term cost |
|---|---|---|---|
| More entry-specific busy flags | Small immediate changes, no migration | Every async gap needs another local check; cross-entry races persist | Multiple resource owners and loading branches remain |
| Shared execution reservation and ASR provider | Replace admission/cleanup ownership; retain feature-specific adapters and existing API contracts | Exercise suspended work, cancellation, snapshot identity and terminal commit | One resource-admission contract and one ASR loader |
| Whole-pipeline rewrite | Reimplement editing, deferred replacement, UI and transports | Much larger regression surface across all retained features | Not justified by the observed defects |

Selected the module-level ownership replacement. VoicePipeline remains the UI/edit adapter; InputSessionCoordinator remains the service adapter. Neither independently decides global resource availability. OpenTypeService retains authenticated API records/events, not ownership of microphone/model execution.

## Invariants

- A MainActor InputSessionOwnership reservation is acquired synchronously before the first preparation await. Menu bar, remote microphone, HTTP/XPC and audio-file processing share the same instance through AppDelegate.
- A cancelled reservation remains occupied until its current asynchronous operation returns. An engine that ignores cancellation must not be reused prematurely. New attempts receive the existing busy behavior; no unbounded queue is added.
- Cleanup verifies reservation identity. Service reset reuses the same ownership/provider, so an old coordinator cannot race its replacement.
- Integration operations own cancellable child tasks and propagate caller cancellation. Client authorization precedes cancellation; XPC disconnect is scoped to its client.
- API history is staged and committed synchronously with the terminal result, after authorization/state validation. No suspension separates these effects.
- VoiceInputSettings captures engine/model, language, vocabulary, processing options and capture choices at admission. Each session retains its engine. Configuration changes take effect next time.
- SpeechEngineProvider is the single production ASR selection/loading path. Its value key includes model, Qwen path, Apple locale and Volc credentials. Cache invalidation does not unload an engine still retained by a session.
- Deferred formatting remains a separately identified background result; existing replacement identity checks and local-model access serialization remain. Applying a replacement acquires the execution reservation.
- Cancellation before text injection suppresses paste/delete fallback and history publication. A keyboard event already delivered to another application cannot be recalled; cancellation does not pretend to undo it.

## Failure and rollback

Engine-not-ready, permission failure, thrown recognition and cancelled callers release only their reservation after cleanup. Cancellation cannot grant another client access or bypass existing authorization. Output-format heuristics and product vocabulary remain unchanged.

Rollback is the inverse of this change's source/test diff; no data migration, dependency update, public payload change, installation or release is required. Do not reset unrelated worktree changes. Restore the prior implementation only as a coherent module change, not one admission check at a time.

## Specialized-text decision

Remove the ignored allowsGuardFallback parameter and identity wrapper. Exercise the actual fidelity decision via validatedOutput, preserving source on rejection. Keep recognized response aliases, all product vocabulary and existing multilingual prompt/heuristic behavior. Their purpose and risk are catalogued in intent.md; unsupported assumptions about their necessity are not deletion authority.
