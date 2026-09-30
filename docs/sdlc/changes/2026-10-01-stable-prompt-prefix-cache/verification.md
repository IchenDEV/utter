# Verification: Stable prompt prefix and KV-cache reuse

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** docs/sdlc/changes/2026-10-01-stable-prompt-prefix-cache/plan.md
**Risk:** medium — model/runtime behavior and user-visible output

Scope: approved slice (spike + stable/volatile assembly split). Local MLX KV
reuse and remote `cache_control` are deferred to follow-up changes.

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Spike: prefix-cache construction path | done (source-level) | See "Spike findings" below |
| `bash scripts/sdlc-checks.sh` | pass | "SDLC checks passed." |
| `bash scripts/ci-basic-checks.sh` | pass | "Basic CI checks passed." |
| `swift test` | pass | 798 tests, 18 skipped, 0 failures; plus 1 Swift Testing suite |
| `swift test --filter StablePromptPrefixTests` | pass | 4 tests, 0 failures |
| `swift build` | pass | "Build complete! (80.88s)" |

Environment note: the active developer directory is `/Library/Developer/CommandLineTools`,
which has no `XCTest`. Tests were run with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

### Spike findings (mlx-swift-lm 3.31.4, source-level)

- Available surface: `ChatSession(_:instructions:cache:)`,
  `savePromptCache(url:cache:metadata:)`, `loadPromptCache(url:)`,
  `makePromptCache(model:parameters:)`, `canTrimPromptCache(_:)`,
  `trimPromptCache(_:numTokens:)`, `KVCache.copy()`, and
  `generate(input:cache:parameters:context:)` with
  `TokenIterator(input:model:cache:parameters:)`.
- `ChatSession.saveCache(to:)` throws `noCacheAvailable` before a generation,
  and `ChatSession` does not expose its cache for mutation (`withCache` is
  internal test support). A prefix-only cache must therefore be built with the
  lower-level `generate(input:cache:parameters:context:)`/`TokenIterator`, or by
  generating one token and trimming back with `trimPromptCache`.
- Conclusion: local KV reuse remains viable, but confirming a clean token
  boundary and token-identical output requires a runtime spike with a real
  model (no model artifact is available in this environment). This is deferred
  to the follow-up change, as approved.

## Acceptance criteria

- For a fixed `(language, style, formatKind, customPrompt, path)` the stable
  prefix is byte-identical across differing volatile inputs —
  **pass** (`testStablePrefixIgnoresVolatileContext`).
- Timestamp and personal/lexicon/edit-rule sections are absent from the prefix
  and present in the volatile tail / user turn — **pass**
  (`testStablePrefixDropsRuntimeTimestamp`,
  `testPersonalContextMovesToVolatileUserTurn`).
- The refactored assembly reproduces the legacy concatenated system prompt —
  **pass** (`testFormattingAssemblyReproducesLegacySystemPrompt`).
- Existing prompt, delimiter, and runtime-context tests still pass —
  **pass** (full `swift test`: 798 passed, 18 skipped).
- `sdlc-checks.sh`, `ci-basic-checks.sh`, `swift test` pass — **pass**.
- Local KV reuse viability recorded — **pass** (spike findings above).

## Residual risk

- The assembly split changes where volatile context appears (user turn instead
  of system). Model-visible content and order are preserved, but providers and
  models can weight roles differently; a real-model manual QA pass on the main
  and command paths is still required before merge.
- The local KV cache and remote `cache_control` are not implemented; the
  performance outcome in the intent is not yet realized.
- Tests were run under `/Applications/Xcode.app` because the ambient
  CommandLineTools toolchain lacks XCTest; CI uses the release-style toolchain.

## Decision

Ready for human review. Evidence recorded; no runtime model QA or performance
measurement has been performed yet.
