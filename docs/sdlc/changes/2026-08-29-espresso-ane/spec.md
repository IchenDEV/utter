# Spec: Add a selectable Espresso ANE inference backend

## Context

`AppSettings` owns persisted model choices, `ModelManagementView` owns model
selection, and `TextProcessor` owns LLM dispatch. Existing local generation uses
`LLMEngine` and MLX; remote generation remains independent. Espresso packages
models and tokenizers as `.esp` directories consumed by `ESPRuntime` and
`RealModelInference`.

## Design

Add a persisted `LocalLLMBackend` choice with MLX as the default and a persisted
Espresso bundle path. The models UI validates a selected directory with
`ESPRuntimeBundle.open`, displays the private-API warning, and requests warmup.

`TextProcessor` owns one `EspressoLLMEngine` actor alongside the MLX engine and
dispatches warmup, readiness, unloading, and generation according to the
captured processing options. The actor retains Espresso's move-only inference
engine, verifies that the bundle resolves to the private ANE backend, applies a
Qwen chat template when appropriate, and returns generated text through the
existing processing pipeline. Remote LLM behavior is unchanged.

For local Espresso warmup and generation, `TextProcessor` first attempts the
selected `.esp` bundle. If that attempt fails, it tries the already-selected
MLX model through the existing `LLMEngine`; `LLMEngine` continues to require a
complete local model and never downloads during fallback. A successful MLX
fallback records a localized notice. The main app consumes that notice, changes
the persisted backend to MLX only if Espresso is still selected, and shows the
notice in the completion state. Integration sessions also persist the backend
change and log it without changing their response schema.

Pin Espresso to the reviewed `v0.9.0` source plus a three-line Swift 6.2
compatibility patch. The patch gives three internal compiled-kernel holder
types package visibility so Xcode 26.6 can resolve metadata references emitted
across the `RealModelInference`, `ESPRuntime`, and app modules. It changes no
runtime logic or public API and avoids taking unrelated upstream `main` changes.

## Safety and failure modes

The model and prompt remain on-device. Espresso depends on private ANE APIs, so
OS or hardware changes can reject generated ANE programs even when bundle
metadata is valid. Such failures first use the selected, installed MLX model;
if MLX is not available or also fails, the combined failure propagates through
the existing model-load or generation error path. Selecting a missing or
malformed bundle does not replace the current setting.

The UI warning explicitly states the private-API and App Store limitation. No
fallback is silent: successful fallback produces a localized status message
and changes the persisted backend to MLX so later requests do not repeatedly
compile a rejected private ANE program. A concurrent user change away from
Espresso is preserved.

The patched dependency is pinned by commit rather than a moving branch. Rollback
returns the package URL and version requirement to upstream `v0.9.0` once an
equivalent fix is released there, or removes Espresso with the rest of this
experimental backend.

## Test strategy

Persistence, prompt formatting, and Espresso-to-MLX fallback ordering and
failure behavior have focused unit tests. The complete Swift suite and
repository checks cover existing paths and package integration. A
release-style app build checks dependency and Metal/resource packaging. Real
inference is exercised with a prepared GPT-2 `.esp` bundle and recorded even if
the host's private ANE compiler rejects it.

## Rollout and rollback

Ship behind an explicit non-default setting. Stop rollout if Espresso cannot
compile a real bundle on the supported release environment. Users can return to
MLX immediately; repository rollback removes the Espresso dependency, engine,
settings fields, and settings UI without migrating stored user data.
