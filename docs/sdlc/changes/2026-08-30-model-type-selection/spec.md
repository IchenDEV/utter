# Spec: Make custom models an explicit recommended-first type

## Context

`selectedModelFamily` currently uses `nil` implicitly for family-less models,
while the picker maps `nil` back to Qwen. `localLLMModelsSection` renders the
custom list and add/import controls after every family. Speech choices use
`SpeechEngineType.allCases` order after filtering MiMo.

## Design

Define one ordered formatting presentation enum with five cases: Qwen, Gemma,
Llama, Remote, and Custom. The Qwen case exposes a recommendation flag and a
picker title containing the localized recommended marker. Local-family cases
map to `ModelCatalog.ModelFamily`; Custom maps to the existing `nil` family;
Remote maps to `settings.useRemoteLLM`.

The segmented picker remains one row in the grouped form. It uses the full
available section width, native compact height, and no nested background.
Custom content uses the same 8/12-point internal rhythm as current model rows.

`syncSelectedFamilyFromActiveModel()` assigns the active entry's family even
when it is `nil`, making family-less custom/imported models select Custom.
Browsing types does not change `settings.llmModel`. Leaving Remote preserves
the existing conditional load callback for the currently active local type.

Speech presentation order becomes explicit and independent from persisted enum
declaration order: Qwen, Whisper, Apple, Doubao. Qwen's title includes the same
localized recommendation marker.

## Safety and failure modes

- A fifth formatting segment can clip in English. Real-window verification
  checks both languages; labels remain short and use the native control.
- `nil` must mean Custom only in this UI selection layer; catalog model-family
  semantics remain unchanged.
- Switching from Remote to Custom must not load a Qwen model accidentally.
- Existing custom models must remain visible and actionable under Custom.

## Test strategy

- Focused tests assert both explicit type orders and Qwen recommendation state.
- Full tests cover settings persistence and model catalog invariants.
- Repository SDLC/basic checks and a verified app build must pass.
- Real-window checks cover both selectors and Custom content across Chinese/
  English and light/dark appearances.

## Rollout and rollback

Merge only after independent high-risk verification, visual approval, and the
normal PR gate. If type selection changes the active model or labels clip,
revert the seven governed source/localization files and their focused test;
persisted settings remain readable because raw values and model IDs did not
change. No data migration or production rollout action is needed.
