# Spec: Replace Espresso with a packaged ANE-LM runtime

## Context

`TextProcessor` already owns one actor for the optional ANE backend and already
serializes local-model operations with MLX fallback. `ModelManagementView`
already owns local model selection. The current Espresso package crosses both
seams. ANE-LM supplies Qwen3 tensor loading, CPU operators, sampling, and private
ANE program compilation, but its CLI tokenizer and CMake-only packaging are not
needed by Utter.

## Design

Fork ANE-LM under `IchenDEV` and expose a single SwiftPM C++ library product. Its
public surface is a C ABI for runtime creation/destruction and token generation.
The handle owns one Qwen3 model, resets its KV cache before each independent
request, invokes a token callback, and treats a callback stop as cancellation.
Errors cross the ABI as owned UTF-8 strings with one matching free function.

The M5 compatibility patch uses current MIL syntax and only single-output ANE
programs. Q, K, and V weights are packed row-wise before compilation and emitted
by one projection. Gate and up weights use the same layout; SiLU and elementwise
multiplication remain on CPU, and down projection remains one ANE program. This
keeps Qwen3 at four layer programs, avoiding both the compiler's fused/multiple-
output rejection and the host's finite ANE program resource limit.

Swift keeps prompt construction and tokenization. `AutoTokenizer` loads from the
selected model folder, the existing chat prompt is encoded without added special
tokens, native generation returns token IDs, and Swift decodes the final IDs.
This avoids bringing ANE-LM's CLI, Jinja, or tokenizers-cpp dependency into the
app. Only `model_type == qwen3` with complete single-file or HF-indexed sharded
safetensors weights is admitted in this first version; unsupported directories
fail validation before native loading.

The existing stored `.espresso` backend value, model-path key, engine property,
and fallback outcome identifiers remain internal compatibility names for this
change. Their behavior changes to ANE-LM while user-visible text says ANE or
ANE-LM. This preserves existing installations and avoids a second migration or
parallel model-management system. The external Espresso dependency and bundle
validation are removed completely.

## Safety and failure modes

Model loading can fail because files are incomplete, tensors do not match the
supported Qwen3 layout, private symbols change, compilation is rejected, or ANE
resources are exhausted. Validation handles structural failures; native errors
then follow the existing explicit fallback policy. No failure silently changes
the backend unless MLX actually completes the request.

The native handle is actor-isolated. A new path or explicit unload destroys it;
cancellation stops the callback loop; each independent request resets model
state. The app must not call through a destroyed handle. Generated error strings
and temporary token buffers have one owner on each side of the C boundary.

The API remains private and therefore unsuitable for Mac App Store distribution.
The selection UI retains this warning. Compatibility claims are limited to real
evidence recorded in verification.

## Test strategy

Focused tests cover directory validation, prompt token flow, fallback enabled
and disabled behavior, and engine lifecycle seams. The exact fork revision is
built through SwiftPM. A real Qwen3-0.6B model exercises direct generation on the
available M5 host, followed by 20 same-process short requests with resident-memory
samples and an unload sample. Repository checks, the full Swift suite, and a
release-style app build cover integration and packaging. An independent verifier
reviews ABI ownership, fallback semantics, dependency provenance, and evidence.

## Rollout and rollback

ANE remains explicit and non-default. Stop rollout on compiler rejection,
unbounded memory, corrupted output, or a lifecycle crash. Rollback restores the
pinned Espresso dependency and engine implementation from the preceding commit;
the persisted backend and path keys require no data migration. Publishing or
releasing the app remains a separate protected human action.
