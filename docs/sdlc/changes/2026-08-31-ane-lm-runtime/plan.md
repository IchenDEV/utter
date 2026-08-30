# Plan: Replace Espresso with a packaged ANE-LM runtime

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [spec.md](spec.md)

## Work items

- [x] Reduce the successful M5 proof of concept to the required Qwen3 program
  layout and remove exploratory kernels.
- [x] Add a narrow C ABI and SwiftPM library product to `IchenDEV/ANE-LM`.
- [x] Pin the reviewed fork revision and remove Espresso products.
- [x] Replace bundle validation with supported Qwen3 directory validation.
- [x] Connect Swift tokenization to native generation through the existing ANE
  actor and local-model lifecycle.
- [x] Preserve enabled and disabled MLX fallback behavior and settings migration.
- [x] Update localized private-API and compatibility copy.
- [x] Add focused behavioral tests where the changed seams are deterministic.
- [x] Exercise real M5 generation, cancellation, unload, and 20-request memory.
- [x] Resolve and close independent verifier findings.

## Verification plan

- [x] Focused package build and runtime tests in the ANE-LM fork.
- [x] Real Qwen3-0.6B generation on M5 Max/macOS 27.
- [x] Same-process 20-request resident-memory sample and post-unload sample.
- [x] Focused ANE selection and fallback tests.
- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] `bash scripts/build-app.sh`
- [x] Independent high-risk verification.

## Human gates

The user explicitly requested the ANE-LM modification and current-project
integration after reviewing the original-runtime failure and proof-of-concept
result. PR approval, acceptance of residual private-API risk, and any release or
publication remain separate maintainer decisions.
