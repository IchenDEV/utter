# Spec: Stable prompt prefix and KV-cache reuse

**Status:** approved
**Approved-by:** chenli (explicit implementation instruction in this chat)
**Approved-date:** 2026-10-01
**Upstream:** docs/sdlc/changes/2026-10-01-stable-prompt-prefix-cache/intent.md
**Risk:** medium — model/runtime behavior and user-visible output

**Scope of this change (approved slice):** design spike + behavior-preserving
stable/volatile assembly split, with volatile context moved to the user turn.
The local MLX prefix cache (section 2) and the remote `cache_control` change
(section 4) are designed here but **deferred** to follow-up changes after the
spike result. Sections marked "(Deferred)" are not implemented here.

## Context

Prompt assembly today (verified):

- `PromptBuilder.buildSystemPrompt` (`Sources/Prompts/PromptBuilder.swift:4`)
  appends, in order: base system prompt and ASR rules (stable per language),
  style and few-shot sections (stable per style+language), then
  `formatContractSection` (derived from transcript/format), then
  `processingContextSections` (input target, screen text, screen-image flag,
  memory, runtime timestamp).
- `TextProcessor.systemPromptWithPersonalContext`
  (`Sources/Processing/TextProcessor+PromptConstruction.swift:74`) then appends
  industry lexicon, personal dictionary, and edit rules — all transcript/user
  dependent.
- `TextProcessor+Generation.swift:32` sends the single string to
  `LLMEngine.generate`, which builds a fresh `ChatSession` per call
  (`Sources/LLM/LLMEngine.swift:42`).
- Remote: `RemoteLLMClient` puts the whole string in the system role (OpenAI
  `RemoteLLMClient.swift:150`) or top-level `system` field (Anthropic
  `:199`).
- The pinned dependency `mlx-swift-lm` 3.31.4 exposes prompt caching:
  `ChatSession(_:instructions:cache:)`, `savePromptCache`/`loadPromptCache`,
  `makePromptCache`, `canTrimPromptCache`/`trimPromptCache`, and
  `KVCache.copy()` for a deep copy. `ChatSession`'s own cache is not exposed
  for mutation, so reuse across independent one-shot requests is done by
  holding a canonical prefix `[KVCache]` and seeding a per-request session from
  a copy.

No golden/full-string prompt snapshots exist; prompt tests assert substrings
and one `hasPrefix` on the custom-prompt path
(`Tests/OpenTypeTests/PromptBuilderTests.swift:213`).

## Design

### 1. Split prompt assembly into stable prefix and volatile tail

Introduce a value type (new file, e.g. `Sources/Prompts/PromptAssembly.swift`):

```swift
struct PromptAssembly {
    let stablePrefix: String   // cacheable; settings-only
    let volatileContext: String // per-request; empty when nothing applies
    let userContent: String     // transcript / command / selection payload
}
```

`PromptBuilder` gains assembly builders that mirror today's builders:

- `buildFormattingAssembly(...)`: `stablePrefix` = custom prompt + output
  contract (custom path) or base + ASR rules + style + few-shot; plus
  `formatContractSection` when `formatKind != nil` (stable per `formatKind`).
  `volatileContext` = input target + screen text + screen-image note + memory +
  runtime timestamp + lexicon/dictionary/edit-rule sections.
- `buildCommandAssembly(...)`: `stablePrefix` = `commandSystemPrompt`;
  `volatileContext` = the command context sections + personal block.

Static guidance about how to treat screen/memory/input-target data stays in the
stable prefix (worded to refer to data provided in the user turn); only the
data blocks move to `volatileContext`. The existing `buildSystemPrompt` /
`buildCommandSystemPrompt` remain as thin wrappers returning
`stablePrefix + "\n\n" + volatileContext` so existing behavior/tests stay
intact until each caller migrates.

`TextProcessor` composes the final user turn as
`volatileContext + "\n\n" + userContent` (with the existing `PromptTextBlock`
delimiters preserved), and passes `stablePrefix` as the system prompt.

### 2. (Deferred) Local MLX prefix cache

Add a small cache owned by `LLMEngine` (actor-isolated):

```swift
struct PrefixKey: Hashable { modelID, prefixHash, chatTemplateContext }
```

- `generate(prefix:volatileContext:prompt:...)`:
  1. Build the full user turn string.
  2. On key hit: `ChatSession(container, instructions: nil,
     cache: copy(cachedPrefix))`, then `respond(to: userTurn)`.
  3. On miss: build the canonical prefix cache (spike path below), store it
     under the key (LRU, cap ~2, cleared on `loadModel`/`unload`), then seed a
     copy for this request.
  4. Any mismatch/ambiguity → use a fresh `ChatSession(instructions: prefix)`
     (today's behavior). Reuse never changes correctness.
- Try to keep one warm `ChatSession` for the most recent prefix and reuse it
  directly within the same key by trimming the cache back to the prefix length
  after each response; otherwise new-session-from-copy.

### 3. Cache construction spike (de-risk before implementation)

`ChatSession.saveCache` requires a prior generation. Determine the cheapest
correct way to obtain a cache that encodes **only** the stable prefix,
including chat-template boundary tokens:

- Preferred: prepare `UserInput(chat: [.system(prefix)])`, run one
  `generate(...)` pass with `maxTokens: 1`, then
  `trimPromptCache(cache, numTokens: generatedAndTrailingTokens)` back to the
  prepared prefix token count; save via `savePromptCache`.
- Confirm the trimmed prefix cache, when seeded into a new session and given
  the same user turn, yields token-identical output to a fresh session for a
  deterministic sampler (temperature 0 / fixed seed).
- If no clean trim boundary exists, fall back to storing the entire
  system+first-user prefix (larger but still stable only if the user turn is
  stable — it is not, so this fallback means no cache and is rejected).

### 4. (Deferred) Remote backend

- Send only `stablePrefix` as the system message/field; put
  `volatileContext + userContent` in the first user message.
- Anthropic: add `cache_control: {type: "ephemeral"}` to the system block when
  the feature flag is on and the prefix exceeds the provider minimum. OpenAI:
  rely on automatic prefix caching once the prefix is stable.
- Gate behind a settings flag (default off for v1) so the ordering change is
  reversible.

### Non-goals

- No change to ANE/Espresso: `ane_lm_generate` takes the full prompt each call
  and exposes no prefix reuse.
- No VLM image cache in v1; the split still applies, images remain per request.
- No on-disk persistence of prefix caches in v1.

## Safety and failure modes

- **Coherence risk (highest):** a wrong trim boundary or stale cache produces
  garbled output. Mitigation: cache key includes the exact prefix string hash
  and template context; on any doubt use a fresh session; add a
  deterministic-sampler equality test and a debug log of hit/miss.
- **Stale cache:** settings/style/model changes change the prefix string and
  therefore the key; caches are cleared on `loadModel`/`unload` and never
  persisted.
- **Memory:** bound to a small LRU of prefix caches; release on model unload
  and on memory pressure notifications.
- **Concurrency:** local model use is serialized by `withLocalModelAccess`;
  prefix caches are immutable canonical state, and each session gets a deep
  copy (`KVCache.copy()`), so no shared mutable KV state.
- **Privacy:** no new fields are sent; remote ordering changes only. Anthropic
  `cache_control` retention is provider-side and must be stated in settings
  copy.
- **Behavioral drift:** moving volatile context to the user turn can change
  model answers. Mitigation: keep the static instruction that explains the
  data, preserve delimiters, and compare cached vs non-cached outputs plus a
  manual QA pass before enabling by default.

## Test strategy

- Unit: stable-prefix byte-equality across differing volatile inputs;
  volatile sections absent from the prefix and present in the user turn;
  assembly ordering and delimiter tests updated.
- Unit: prefix-cache key identity/invalidation; LRU bound; fallback on miss.
- Integration (MLX, deterministic sampler): cached vs non-cached output
  equality for main/command/edit-resolver, Chinese and English.
- Performance observation: cold vs warm prefill timing and a cache-hit log
  line (manual, recorded in `verification.md`).
- Manual: real-window dictation QA on the main path with screen context and
  personal dictionary enabled; confirm output quality unchanged.
- Existing suites: `PromptBuilderTests`, `MultilingualPromptTests`,
  `MemoryContextFactBoundaryTests`, `RuntimeContextPromptTests`,
  `PromptDelimiterSafetyTests`, `SelectionEditPromptTests`.

## Rollout and rollback

- Land the assembly split first (no behavior change; wrappers preserve the
  concatenated string). Then add the MLX cache behind a settings flag. Then
  remote `cache_control` behind a separate flag.
- Rollback: disable the flags to return to per-request full prefill; the
  assembly split alone is behavior-preserving via the legacy wrappers, so
  reverting the cache leaves quality unchanged.
- Stop condition: any deterministic-sampler mismatch or reported quality
  regression disables the cache flag.
