# Intent: Add a selectable Espresso ANE inference backend

## Problem

Utter's local LLM processing is limited to MLX, so users cannot choose an
Apple Neural Engine runtime for local post-processing.

## Outcome

The model settings let users choose Espresso, select an `.esp` model bundle,
and route local warmup and text generation through Espresso's ANE runtime.
Users choose whether an Espresso failure should finish with the selected,
installed MLX model or stop with an Espresso error. Automatic fallback remains
the default and identifies which backend produced the result.

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
- Users can disable automatic MLX fallback while keeping Espresso selected.
- When fallback is enabled, an Espresso runtime failure falls back to an
  installed selected MLX model, persists MLX as the active backend, and
  surfaces the fallback to the user.
- When fallback is disabled, an Espresso runtime failure does not run MLX and
  surfaces an actionable Espresso error.
- If the selected MLX model is unavailable, the Espresso failure remains
  visible with guidance to install an MLX model.
- Repeated fallback requests do not retain request-scoped state, and explicitly
  unloading local models waits for active local inference, releases every
  production model container, and clears MLX's reusable memory cache.
- Existing local MLX and remote LLM behavior remains covered by passing tests.
- The available M5/macOS 27 host rejects Espresso's private ANE program without
  preventing local formatting when a compatible MLX model is installed.

## Open questions

Upstream documents M1 through M4 as tested, but Utter has not independently
verified that matrix. M5 is absent from that matrix, and direct Espresso
inference on the available M5 Max/macOS 27 host is blocked by the ANE compiler.
Because the backend uses private APIs, the failing variable may be the SoC, the
OS, or their combination; current evidence does not prove an M5-only failure.
