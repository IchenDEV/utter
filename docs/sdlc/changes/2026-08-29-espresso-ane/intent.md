# Intent: Add a selectable Espresso ANE inference backend

## Problem

Utter's local LLM processing is limited to MLX, so users cannot choose an
Apple Neural Engine runtime for local post-processing.

## Outcome

The model settings let users choose Espresso, select an `.esp` model bundle,
and route local warmup and text generation through Espresso's ANE runtime. If
that private runtime fails and the selected MLX model is installed, Utter
completes the request with MLX, switches the persisted backend to MLX, and
shows which backend produced the result.

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
- An Espresso runtime failure falls back to an installed selected MLX model,
  persists MLX as the active backend, and surfaces the fallback to the user.
- If the selected MLX model is unavailable, the Espresso failure remains
  visible with guidance to install an MLX model.
- Existing local MLX and remote LLM behavior remains covered by passing tests.
- The available M5/macOS 27 host rejects Espresso's private ANE program without
  preventing local formatting when a compatible MLX model is installed.

## Open questions

Which macOS 27 and M5 combinations Espresso will support remains an upstream
compatibility question. Direct Espresso inference on the available M5
Max/macOS 27 host is currently blocked by the ANE compiler.
