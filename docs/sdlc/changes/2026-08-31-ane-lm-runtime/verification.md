# Verification: Replace Espresso with a packaged ANE-LM runtime

**Status:** approved
**Approved-by:** IchenDEV (user)
**Approved-date:** 2026-08-31
**Upstream:** [plan.md](plan.md)

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Exact dependency | Pass | `Package.swift` and `Package.resolved` resolve `IchenDEV/ANE-LM` at immutable revision `033472ec12ea796fc7ea4f8cefd7ed456f69900b`; no Espresso package or product remains. |
| Fork package build | Pass | `swift build -c release` passed for the fork; its CMake CLI also rebuilt after parser and cleanup hardening. |
| Fork CLI smoke | Pass | Rebuilt CLI generated two tokens from the official Qwen3-0.6B model at 19.197 prompt tok/s and 18.904 generation tok/s after the mapped-allocation change. |
| Model validation | Pass | Focused tests accept a structurally complete synthetic Qwen3 model and reject truncated or missing weights, F16, unsupported config, missing or malformed tokenizer data, unsupported tokenizer components, out-of-range token IDs, missing or non-special ChatML boundary tokens, an EOS mismatch, and an invalid GQA head ratio before loading ANE. |
| Real M5 Qwen3 generation | Pass | The Utter Swift tokenizer → pinned C ABI → private ANE path generated non-empty output on M5 Max/macOS 27 without MLX fallback. |
| Three-lifecycle memory sample | Pass | 20 requests across three complete load/generate/unload lifecycles, plus cancellation in the final lifecycle, passed in 84.367s. Within-lifecycle RSS growth was 80 KB, 32 KB, and 0 KB, each below the 16 MiB bound. Unload released more than 512 MiB from every lifecycle peak; the three sampled post-unload minima were 636,512 KB, 150,928 KB, and 662,592 KB. The final minimum was 26,080 KB above the first and below the enforced 128 MiB cross-lifecycle bound. |
| Fallback behavior | Pass | Existing enabled, disabled, load-failure, generation-failure, and cancellation policy tests pass in the full suite; selection changes only after native structural validation succeeds. |
| `bash scripts/sdlc-checks.sh` | Pass | The strict shell gate checked all 12 change bundles after merging current `main`; the active intents remain pending human approval and later stages remain draft. |
| `bash scripts/ci-basic-checks.sh` | Pass | Package, shell SDLC gate, plist and localization, identifiers, vocabulary, resources, conflict, secret-bearing file, and symlink checks passed after conflict resolution. |
| `swift test` | Pass | 592 XCTest cases passed, 10 environment-gated cases skipped, and the Swift Testing model-upgrade test passed after the final runtime and UI changes. |
| `bash scripts/build-app.sh` | Pass | The final no-hook `Utter.app` and `Utter-0.0.43.dmg` built; app and mounted-DMG signatures passed and the DMG checksum verified. |
| Real-window UI | Pass | Actual 760 by 680 settings window exposed the ANE selector, Qwen3 directory chooser, enabled MLX fallback, and private-API/App Store warning with no clipping. |
| Independent verification | Pass | Final P1/P2-only review returned CLEAN after confirming ChatML boundary-token validation, the three tokenizer regressions, lifecycle evidence wording, and plan/verification consistency. |

## Acceptance criteria

- Exact fork pin and Espresso removal — Pass.
- Qwen3 directory validation — Pass, including required tensor, shape, BF16
  dtype, safe header, and tokenizer checks before saved selection changes.
- Real M5 ANE generation — Pass for official Qwen3-0.6B on the available M5
  Max/macOS 27 host.
- User-selectable MLX fallback — Pass in existing policy tests and real UI.
- Cancellation, unload, and bounded repeated-generation memory — Pass across
  three complete lifecycles with one cancellation: 80/32/0 KB within-lifecycle
  growth, at least 512 MiB recovery from each peak, and 26,080 KB final growth under the enforced
  128 MiB cross-lifecycle bound.
- Existing MLX and remote behavior — Pass in the full suite.
- Release-style packaging — Pass for the final no-hook app and mounted DMG.
- Private-API and compatibility disclosure — Pass in both localizations and the
  real settings window.

## Residual risk

Only Qwen3-0.6B on one M5 Max/macOS 27 host has real product-path evidence.
Qwen3.5, other parameter sizes, other Apple Silicon devices, macOS 26, and
future operating-system versions remain outside the compatibility claim. The
runtime uses private APIs, has no ABI stability promise, and is not suitable for
Mac App Store distribution. Loading still compiles 122 private ANE programs and
can fail under resource pressure; the corrected path now cleans partial state
and follows the explicit fallback policy instead of retaining it. Post-unload
RSS was not deterministic: the three observed minima varied between 150,928 KB
and 662,592 KB even though request-time and cross-lifecycle growth stayed
bounded. `vmmap` and a standalone allocation probe indicate that allocator
reclaim timing contributes, but this test does not completely isolate framework
or private-runtime retention. The UI therefore only states that memory may not
immediately return to its pre-load level after switching away.

## Decision

Implementation evidence and the strict shell governance gate are ready for
review after merging current `main`; no release or human approval is recorded.
