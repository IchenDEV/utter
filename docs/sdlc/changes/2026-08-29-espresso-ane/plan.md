# Plan: Add a selectable Espresso ANE inference backend

## Work items

- [x] Add and resolve the Espresso Swift package products.
- [x] Persist the local backend and Espresso bundle path with MLX defaults.
- [x] Add bundle selection, validation, localization, and private-API warning.
- [x] Route local warmup, readiness, unload, and generation to Espresso.
- [x] Add focused settings and prompt-format tests.
- [x] Exercise a prepared GPT-2 bundle on the available ANE host.
- [x] Merge current `origin/main` and preserve both dependency sets.
- [x] Resolve independent-review findings for error visibility, stale preload state, and path privacy.
- [x] Diagnose the Xcode 26.6 Release linker failure and pin the minimal Espresso metadata fix.
- [x] Fall back from failed Espresso warmup and generation to an installed MLX model.
- [x] Persist MLX after successful fallback and surface a localized completion notice.
- [x] Cover fallback ordering, success, and dual-failure behavior with focused tests.
- [x] Scope fallback outcomes to one request and preserve actionable dual-failure guidance.
- [x] Reproduce retained MLX memory after unload and clear the MLX cache on explicit unload.
- [x] Share one processor across voice and integration workflows and include benchmarking in its lifecycle.
- [x] Serialize complete local-model transactions and remove cancelled waiters from the lifecycle queue.
- [x] Let users disable automatic MLX fallback while preserving it as the default.
- [x] Keep Espresso selected and surface its runtime error when fallback is disabled.
- [x] Clarify in-product compatibility copy without claiming an M5-only failure.
- [x] Resolve independent-review findings for latest-operation outcomes, cancellation, and file size.

## Verification plan

- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] Targeted `ConfigurationTests`
- [x] Release-style app build
- [x] Real GPT-2 `.esp` inspection and generation attempt
- [x] GitHub Xcode 26.6 release-style app build after the dependency pin
- [x] Real M5 ANE compile matrix across deployment targets and normalization variants
- [x] Targeted Espresso fallback tests
- [x] Current full repository gates and release-style app build
- [x] Repeated real fallback requests and explicit-unload memory regression
- [x] Independent cancellation, unload-order, shared-ownership, and file-size review
- [x] Focused disabled-fallback and persistence tests
- [x] Real settings-window light and dark verification for the fallback control
- [x] Current repository gates and release-style app build after the follow-up

## Human gates

A maintainer must decide whether to merge while M5 Max/macOS 27 inference is
blocked upstream. Publishing or releasing remains a separate approval.
