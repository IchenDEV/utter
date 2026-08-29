# Intent: Add a selectable Espresso ANE inference backend

## Problem

Utter's local LLM processing is limited to MLX, so users cannot choose an
Apple Neural Engine runtime for local post-processing.

## Outcome

The model settings let users choose Espresso, select an `.esp` model bundle,
and route local warmup and text generation through Espresso's ANE runtime.

## Scope

This change covers the local LLM backend setting, Espresso bundle selection,
runtime dispatch, persistence, localization, and dependency integration. It does
not create or download Espresso bundles, alter speech recognition, or claim App
Store compatibility for Espresso's private ANE API.

## Constraints

- Utter remains local-first and sends no new data to a remote service.
- The existing MLX backend remains the default.
- Espresso uses private Apple APIs and may fail across macOS or SoC revisions.
- Model preparation remains an upstream Espresso workflow.

## Acceptance criteria

- MLX and Espresso are selectable local LLM backends and the choice persists.
- A valid `.esp` directory can be selected while malformed bundles are rejected.
- Espresso selection routes warmup and generation through the Espresso engine.
- Existing local MLX and remote LLM behavior remains covered by passing tests.
- Real text generation succeeds on a supported Apple Silicon/macOS combination.

## Open questions

Which macOS 27 and M5 combinations Espresso will support remains an upstream
compatibility question. Real inference on the available M5 Max/macOS 27 host is
currently blocked by the ANE compiler.
