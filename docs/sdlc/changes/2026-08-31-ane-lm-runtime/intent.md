# Intent: Replace Espresso with a packaged ANE-LM runtime

**Status:** approved
**Approved-by:** IchenDEV (user)
**Approved-date:** 2026-08-31
**Upstream:** User request and PR #86

## Problem

The selectable ANE backend currently depends on Espresso, whose bundled ANE
program is rejected by the private compiler on the available M5 Max/macOS 27
host. The original ANE-LM project also fails there because its fused projection
programs are rejected, even though smaller single-output ANE convolutions work.

## Outcome

Utter uses a reviewed ANE-LM fork whose Qwen3 projection layout compiles on the
available host. Users keep the existing ANE selection and optional MLX fallback,
while selecting an ordinary local Qwen3 Hugging Face model directory instead of
an Espresso bundle.

## Scope

This change packages the smallest ANE-LM inference runtime as a Swift package,
integrates load, generation, cancellation, reset, and unload into the existing
local-model lifecycle, updates model validation and product copy, and verifies
real Qwen3-0.6B inference. It does not add model download management, change the
MLX or remote backends, support training, or claim support for untested model
families and Apple devices.

## Constraints

- All prompts, weights, and generated tokens stay on-device.
- The runtime uses private Apple ANE APIs and is not App Store compatible.
- MLX remains the default local backend and the user controls fallback.
- Existing persisted backend and model-path keys remain readable.
- The fork is pinned to an immutable commit; no moving branch is accepted.
- Runtime ownership must be explicit so unload does not retain model weights or
  compiled programs.

## Acceptance criteria

- The app resolves an exact `IchenDEV/ANE-LM` revision and removes Espresso.
- Selection accepts a complete Qwen3 directory and rejects missing or unsupported
  configuration and weight files without replacing the saved selection.
- The available M5 Max/macOS 27 host generates non-empty Qwen3-0.6B output on ANE
  without invoking MLX fallback.
- Enabled fallback completes with the selected installed MLX model after an ANE
  error; disabled fallback keeps ANE selected and exposes the ANE error.
- Cancellation stops token generation, and explicit unload destroys the native
  runtime before clearing reusable MLX allocations.
- A repeated real-generation sample has no sustained post-warmup growth above
  16 MiB across 20 short requests; any unavoidable retained allocation is
  measured and documented.
- Existing automated tests and a release-style app build pass.
- User-visible copy identifies this as experimental private-API ANE support and
  does not promise compatibility beyond tested evidence.

## Open questions

The proof of concept covers Qwen3-0.6B on one M5 Max/macOS 27 host. Qwen3.5,
other parameter sizes, older Apple Silicon, and future operating systems remain
outside this change until independently exercised.
