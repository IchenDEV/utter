# Spec: Desktop Copy and Apply-replacement buttons must start a session

**Status:** approved
**Approved-by:** User, answered the approval question in this conversation: approve
**Approved-date:** 2026-10-30
**Upstream:** [intent](intent.md)

## Context

- Desktop actions go through `NativeDesktopHost.start(_:)` into
  `SessionDriver.start`, which is `admit(intent, activate: true)`.
- `SessionInput.unselected` means "a session that still waits for an input
  source". The integration API creates such sessions on purpose
  (`OpenTypeService+Creation`) and binds the source later with
  `SessionDriver.activate(_:input:)`.
- `NativeDesktopHost.copy` and `applyReplacement` also send `.unselected`, but
  their operations (`.copy`, `.applyReplacement`) consume no input source: they
  deliver text that already exists.
- `admit` binds a source for every `.unselected` intent:
  `if activate, intent.input == .unselected { try job.bind(input: .local) }`.
  Only `VoiceSessionJob` implements `bind`; the protocol default throws
  `invalidSessionState`, so the two operations are rejected before any job runs.
- `SessionWorkflowFactory.willActivate` already uses `intent.operation == .input`
  to separate "operations that capture or consume input" from the rest.
- Production shipping tests use `.local` for the same operations, which is why
  nothing failed in CI. See the intent for the evidence and the regression origin.

## Design

Chosen: gate the local binding in `SessionDriver.admit` by operation.

```swift
if activate, intent.input == .unselected, intent.operation == .input { try job.bind(input: .local) }
```

- Scope of the change: one condition in `Sources/UtterSession/SessionDriver.swift`.
  Non-input operations never need a source, so they start with their intent as
  built; the frozen intent keeps `input == .unselected`.
- Nothing else reads the active intent's `input` for these operations: the only
  other readers are `VoiceWorkflowFactory.make` (after the early returns for
  `.copy`/`.restoreSelectionEdit`/`.applyReplacement`) and `VoiceSessionJob`.
  `activate(_:input:)` requires `phase == .created`; these sessions start in
  `.preparing`, so a later `activate` for their id is still `invalidSessionState`.
- `NativeDesktopHost`, `CopySessionJob`, `DeferredReplacementJob`,
  `RestoreSelectionEditJob`, and the `SessionJob` protocol default are unchanged.

Rejected alternatives:

- Host sends `.local` (what the tests do): fixes today's two callers but leaves
  `.unselected` + non-input operations a trap for any future entry point, and
  labels a non-capturing action as local capture.
- No-op `bind` in `CopySessionJob` and `DeferredReplacementJob`, or a no-op
  protocol default: more code in more files, and a no-op default would weaken the
  guard for any job that must not accept a source.

## Safety and failure modes

- No permission, privacy, signing, or dependency change. The clipboard write is
  the same `ClipboardPasteTransaction.copy` transaction already used by the
  `.local` tests; no dictated text is added to any log.
- Voice dictation started with `.unselected` (operation `.input`) still binds
  `.local`; integration sessions are untouched (they never reach this branch with
  a non-input operation because `VoiceWorkflowFactory.make` rejects
  `intent.clientID != nil` for `.copy`/`.applyReplacement`).
- Whitespace-only copy still throws in `CopySessionJob.init` before a job exists,
  so it still refuses to start (and the host still only logs).
- Failure containment: if the condition were wrong, the visible symptom would be
  today's symptom (log line `Desktop action could not start`), not data loss.

## Test strategy

| Acceptance criterion | Check | Level |
|---|---|---|
| Copy via `.unselected` ends `copied`, exact text, no history/anchor change | `host.copy("...")` on a real `NativeDesktopHost` over the production runtime and `SessionDriver` (`VoiceWorkflowFixture`); assert the single `.clipboard(text)` request, `deliveryStatus == .copied`, empty history, unchanged recent-output anchor. Must fail on `0e0f3c1` with `invalidSessionState`. | Automated, end to end |
| Apply-replacement via `.unselected` ends like the `.local` tests | `host.applyReplacement()` with an installed pending replacement; mirror the existing `.local` expectations (expired -> clipboard copy, ready -> anchored replace). | Automated, end to end |
| Host and test intents cannot drift | The tests above call the host's own entry points; none builds the intent by hand. | Automated |
| Whitespace-only copy refuses | `host.copy("  \n")` starts nothing: no request, no snapshot change. | Automated |
| `.unselected` voice dictation still binds; restore unchanged | `SessionDriverTests`: a fake job records `bind`; `.input` + `.unselected` binds `.local`, `.copy` + `.unselected` does not. Existing restore tests stay green. | Automated, unit |
| Real clipboard and log in a running app | Development build: History copy button and context menu, menu bar copy buttons; `pbpaste` equals the shown text; unified log has no `Desktop action could not start`. | Manual, real window |
| Repo gates | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`. | Automated |

## Rollout and rollback

- One small commit plus tests; ships in the next patch release through the normal
  release pipeline (a separate human-gated action, not part of this change).
- Observe after release: the log line `Desktop action could not start` should not
  appear on Copy clicks.
- Rollback: revert the commit. No data, settings, or file-format change is
  involved.
