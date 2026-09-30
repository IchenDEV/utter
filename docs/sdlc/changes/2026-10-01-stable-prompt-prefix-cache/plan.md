# Plan: Stable prompt prefix and KV-cache reuse

**Status:** approved
**Approved-by:** chenli (explicit implementation instruction in this chat)
**Approved-date:** 2026-10-01
**Upstream:** docs/sdlc/changes/2026-10-01-stable-prompt-prefix-cache/spec.md
**Risk:** medium — model/runtime behavior and user-visible output

## Work items

- [x] Spike: confirm the pinned `mlx-swift-lm` 3.31.4 prefix-cache construction
  path (system-only prefill + `trimPromptCache` to the prepared prefix length,
  or an equivalent) and record token counts plus a deterministic equality
  check in `verification.md`. This is investigation only; report the result
  and whether local KV reuse remains viable before writing cache code.
- [x] Add `PromptAssembly` and split the main formatting builder into
  `stablePrefix` / `volatileContext` / `userContent`; keep
  `buildSystemPrompt` as a concatenating wrapper (no behavior change).
- [x] Split the command builder the same way; translation already has no
  volatile system context. Selection edit and the edit-command resolver now
  carry their personal context in the user turn instead of the system prompt.
- [x] Move the volatile data blocks to the user turn as
  `volatileContext + "\n\n" + userContent`, preserving the static instruction
  and `PromptTextBlock` delimiters; keep static guidance about how to use the
  data in the stable prefix.
- [x] Keep existing prompt unit tests passing: `buildSystemPrompt`,
  `buildCommandSystemPrompt`, `formattingSystemPrompt`, `commandSystemPrompt`,
  `systemPromptWithPersonalContext`, and
  `selectionEditSystemPromptWithPersonalContext` are unchanged in signature and
  concatenated output.
- [x] Add a unit test asserting the stable prefix is byte-identical across
  requests whose volatile inputs differ.
- [x] Record evidence and residual risk in `verification.md`.
- [ ] (Deferred, separate change) local MLX prefix cache behind a flag.
- [ ] (Deferred, separate change) remote ordering + Anthropic `cache_control`.

## Verification plan

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] Spike equality check (deterministic sampler) recorded in
  `verification.md`.
- [ ] Manual real-window QA: dictation on main path with screen context and
  personal dictionary enabled; compare output to the pre-change build.

## Human gates

- Intent approval: granted in this chat (2026-10-01).
- Spec approval: required before the spike and split are implemented.
- Acceptance of the prompt-behavior change from moving volatile context into
  the user turn: required before merge.
- Decision after the spike on whether to proceed to the deferred local cache
  and remote `cache_control`.
- PR approval: required before merge.
