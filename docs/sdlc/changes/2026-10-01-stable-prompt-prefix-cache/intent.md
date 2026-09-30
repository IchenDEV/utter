# Intent: Stable prompt prefix and KV-cache reuse

**Status:** approved
**Approved-by:** chenli (explicit approval in this chat)
**Approved-date:** 2026-10-01
**Upstream:** —
**Risk:** medium — model/runtime behavior and user-visible output

**Approved scope slice:** the local MLX prefix cache and remote `cache_control`
are deferred. This change delivers the design spike plus the
behavior-preserving stable/volatile assembly split; the deferred halves are
re-scoped after the spike result and a separate approval.

## Problem

Every dictation rebuilds one opaque system prompt that mixes byte-stable
instructions with per-request context, then sends it through a brand-new
`ChatSession`:

- `PromptBuilder.buildSystemPrompt` prepends the stable sections
  (`baseSystemPrompt`, `asrQualityRules`, style, few-shot) but then appends
  volatile sections: `formatContractSection`, input-target/screen/memory
  context, a minute-resolution runtime timestamp
  (`PromptCatalog+RuntimeContext.swift:39`), and the personal
  dictionary/lexicon/edit-rule block (`TextProcessor+PromptConstruction.swift:74`).
- `TextProcessor+Generation.swift` passes the whole blob as one `systemPrompt`
  string; `LLMEngine.generate` then constructs a fresh
  `ChatSession(container, instructions: systemPrompt)` on every call
  (`Sources/LLM/LLMEngine.swift:42`).

Consequences:

- No token prefix is ever reusable: even two consecutive dictations with an
  identical language/style/format re-prefill the entire system prompt, adding
  first-token latency on every request.
- The minute-resolution timestamp and transcript-dependent personal context
  make even the stable leading sections unusable as a cache key.
- The remote path serializes all volatile context into the `system`
  role/field, which defeats OpenAI/Anthropic prompt caching (a cache hit needs
  a byte-stable leading prefix).

This is a **prefill / time-to-first-token** cost, not a model-weight load cost.
Model load time is unaffected by prompt structure.

## Outcome

1. The instruction prefix that depends only on settings (language, style,
   format kind, custom prompt, main vs command path) is byte-stable and
   identical across requests, regardless of screen, memory, input target,
   wall-clock time, personal dictionary, lexicon, edit rules, or transcript.
2. All volatile context moves out of the cached prefix (into the user turn or a
   delimited dynamic tail that follows the prefix).
3. On the local MLX backend, that stable prefix is prefilled once per
   `(modelID, prefix)` and reused for later requests, measurably lowering
   time-to-first-token. Reuse is a pure optimization: any cache miss or
   ambiguity falls back to a full fresh prefill with identical output.
4. On the remote backend, the system message contains only the stable prefix so
   provider-side prompt caching can engage.

## Scope

- Affected: prompt assembly in `Sources/Prompts/` and
  `Sources/Processing/TextProcessor+PromptConstruction.swift`; the local MLX
  generate path in `Sources/LLM/LLMEngine.swift`; the remote serialization in
  `Sources/LLM/RemoteLLMClient.swift`.
- Affected features: main smart-format, command mode, and (as far as the shared
  split allows) selection edit, translation, and the edit-command resolver.
- Non-goals: changing model weights or download/load behavior; changing the
  ANE/Espresso backend (its C API exposes no prefix reuse — documented, not
  fixed here); changing prompt wording except for the mechanical
  move/relabel of volatile sections; adding new prompt content.

## Constraints

- Output quality must not regress. The cache path must produce the same
  tokens as the non-cached path for the same structured input; caching may not
  change model-visible content ordering in a way that changes answers without
  explicit review.
- No new privacy surface: no additional data leaves the device. Remote
  `cache_control` is server-side retention governed by the provider and must be
  documented.
- Local prefix caches are bounded in memory and invalidated on model change,
  settings change, and process exit.
- Must reuse the pinned `mlx-swift-lm` 3.31.4 prompt-cache API
  (`ChatSession(_:cache:)`, `savePromptCache`/`loadPromptCache`,
  `makePromptCache`, `trimPromptCache`); no new dependency.

## Acceptance criteria

- For a fixed `(language, style, formatKind, customPrompt, path)` the produced
  stable prefix string is byte-identical across requests whose screen, memory,
  input target, time, dictionary, lexicon, edit rules, and transcript differ.
- The runtime timestamp and the personal dictionary/lexicon/edit-rule sections
  no longer appear in the cached prefix.
- With a deterministic sampler, cached and non-cached paths produce
  identical output for a representative prompt set (main, command, edit
  resolver; Chinese and English).
- A second identical-configuration local request logs a prefix-cache hit and
  shows lower measured prefill time than a cold request for the same prefix.
- Existing prompt tests continue to assert the same model-visible content
  (updated only for its new location/role); `PromptDelimiterSafetyTests` still
  passes.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and
  `swift test` pass.

## Open questions

- Does `mlx-swift-lm` 3.31.4 offer a prefill-only path to build the prefix
  cache, or must the prefix be built by generating and then trimming the cache
  back to the prefix boundary? (Resolved by the design spike in the spec.)
- Should `formatContractSection` be part of the stable prefix keyed by
  `formatKind`, or treated as volatile? (Proposed: stable, keyed.)
- Should remote `cache_control` be on by default or feature-flagged?
- How many prefix caches to retain, and whether to persist them across
  launches (proposed: in-memory, small LRU, no persistence in v1).
