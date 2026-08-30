# Intent: Make custom models an explicit recommended-first type

## Problem

Custom model entry and local import are rendered beneath every local LLM family
instead of belonging to an explicit type. An active custom model has no family,
so the picker falls back to Qwen. Speech-engine presentation also inherits an
enum order that places the recommended Qwen engine last.

## Outcome

Custom becomes a first-class text-formatting type. Qwen is first and visibly
recommended in both speech and formatting type selectors. Selection state,
content, and the active model remain coherent.

## Scope

In scope: display order and labels of speech/formatting types, custom-type
selection, conditional custom-model controls, and active-model synchronization.

Out of scope: model catalog contents, download/import implementation, default
persisted models, inference behavior, and remote-provider configuration.

## Constraints

- Preserve existing persisted `SpeechEngineType` raw values and LLM model IDs.
- Keep standard native segmented controls and the existing grouped form grid.
- Do not change the active model merely by browsing another type.
- Preserve all unload/load callbacks when leaving or entering Remote.

## Acceptance criteria

- Formatting order is Qwen recommended, Gemma, Llama, Remote, Custom.
- Custom controls and family-less models appear only under Custom.
- Active family-less models synchronize to Custom.
- Speech order is Qwen recommended, Whisper, Apple, Doubao.
- Both selectors fit the fixed window in Chinese/English and light/dark.

## Open questions

None. Human review retains final visual approval.
