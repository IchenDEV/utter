# Intent: Model download retry recovery

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** —

## Problem

A model download that dies part-way through can never be completed afterwards.
The reported symptom is a download that stops after a few megabytes and then
fails again on every retry, surviving restarts and even delete-then-download.

Both download stacks resume by appending to an `.incomplete` file. When the
transfer dies, the leftover partial can no longer be reconciled with the server
(for example a ranged request answered with the full body), so each retry appends
to the same corrupt file and fails on the same byte range. Nothing in the app
removes those markers: "delete" only removes the materialized model directory,
and Whisper partials live inside the shared repository folder.

Two smaller problems compound it:

- cancel only requests task cancellation, so a transfer that ignores it keeps the
  model "downloading" forever and the retry button never returns;
- a transfer that stalls without an error keeps status `downloading` with no
  timeout, so the UI never offers a retry.

## Outcome

After a failed or stalled download the user can always retry from the Models
page and the retry completes. Partial download markers are cleared on retry, so
the transfer restarts from a clean state without discarding completed files.
Delete removes a model's partial markers as well as its materialized files.

## Scope

Affected: model download for Whisper (WhisperKit), local LLM (MLX), and local
ASR (Qwen3-ASR / FireRed / Mega) in Settings → Models and in onboarding.

Non-goals: changing download sources, progress accounting, or model catalogs;
adding automatic unlimited retries; changing the on-disk model layout used by
already-complete models.

## Constraints

- No new dependencies.
- Semantic behavior only; no fixed filesystem paths outside the existing model
  root and the documented Hugging Face cache locations.
- Must not delete completed model files, only partial-download markers.
- Localization keys must stay in parity across `en.lproj` and `zh-Hans.lproj`.

## Acceptance criteria

- Retrying a model whose status is an error removes its `.incomplete` markers
  before the transfer starts and then completes.
- Cancelling a download immediately makes the model resumable, even when the
  underlying transfer has not yet observed cancellation.
- A download that reports no progress for a sustained interval fails with a
  resolved, actionable state instead of a frozen progress bar.
- Deleting a model also removes its partial-download markers.
- `swift test` passes, including new tests for the marker cleanup, the retry
  gate, and the stall watchdog.

## Open questions

None. Threshold choice for the stall watchdog (120 s) is a tunable default.
