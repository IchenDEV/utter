# Intent: Desktop Copy and Apply-replacement buttons must start a session

**Status:** approved
**Approved-by:** User, answered the approval question in this conversation: approve intent, and approve spec and plan together once both are written
**Approved-date:** 2026-10-30
**Upstream:** — (companion: [WeChat dictation ends not-inserted](../2026-10-30-wechat-delivery-no-focus/intent.md))
**Risk:** Medium. User-visible behavior of the desktop output actions; no permission, privacy, signing, or release-pipeline change. Corrective intent for a production regression first shipped in v0.0.51.

## Problem

Every Copy button in the desktop UI does nothing, and so does the menu bar's
"replace with formatted text" button. The dictated text can therefore not be recovered
from the UI after a failed insertion, even though the failure message itself
says "you can copy the text" (`delivery.target_changed`).

### Evidence (2026-10-30, installed Utter 0.0.60, pid 60570)

- Unified log, subsystem `com.opentype.voiceinput`: 11 entries between 15:15:17
  and 15:16:12, each `Desktop action could not start: ... (UtterContracts.IntegrationError error 8.)`.
  Each is preceded by an AppKit `sendAction:` entry, i.e. a button click. The
  NSError code 8 maps to `IntegrationError.invalidSessionState`
  (verified with a standalone Swift enum: code = declaration index + 1 for this
  enum shape).
- Code trace, all in `origin/main` at `0e0f3c1`:
  1. `NativeDesktopHost.copy` builds `SessionIntent(input: .unselected, operation: .copy(text))`;
     `applyReplacement` builds `SessionIntent(input: .unselected, operation: .applyReplacement(id))`
     (`Sources/UtterPresentation/NativeDesktopHost+Actions.swift`).
  2. `SessionDriver.admit(_, activate: true)` runs
     `if activate, intent.input == .unselected { try job.bind(input: .local) }`
     (`Sources/UtterSession/SessionDriver.swift`, line 98).
  3. Only `VoiceSessionJob` implements `bind`. `CopySessionJob` and
     `DeferredReplacementJob` use the protocol default, which throws
     `IntegrationError.invalidSessionState`
     (`Sources/UtterContracts/SessionExecutionService.swift`, line 210).
  4. `NativeDesktopHost.start` catches the error, writes the log line above, and
     returns. The user sees nothing.
- Surfaces that call `NativeDesktopHost.copy`: overlay "Copy", the three menu bar
  popover copy buttons (candidate text, last inserted text, formatted
  replacement text), and the History/Stats row button and context menu. Surface
  that calls `applyReplacement`: the menu bar "replace with formatted text"
  button (`menubar.replace_formatted`).
- Test gap: `CopySessionJobTests` exercises the job directly, and every test that
  drives a `SessionDriver` with a copy or apply-replacement intent uses
  `input: .local`
  (`VoiceReplacementTests`, `VoiceEditingNativeE2ESecureSessionTests`). No test
  builds the intent the way the production entry point does.
- Regression origin: `bind` and its throwing default arrived in `7ba9efa` and the
  `.unselected` desktop intents in `a44dbd7`, both 2026-10-04; the first tag
  containing both is v0.0.51. By source trace only; v0.0.51 was not re-run.

## Outcome

Clicking Copy anywhere in the desktop UI puts the shown text on the clipboard
and records a `copied` delivery. Clicking "apply pending replacement" runs the
deferred replacement (replace in place, or clipboard fallback per the existing
policy). Voice dictation, selection editing, and the HTTP/XPC integration
sessions behave exactly as before.

## Scope

In scope:

- The session start path for desktop-originated, non-capturing operations
  (`.copy`, `.applyReplacement`).
- Regression tests that start these operations the same way the desktop host
  does, through a real `SessionDriver` and the production workflow factory.
- A deterministic guard so the desktop host's intents and the tested intents
  cannot drift apart again.

Non-goals:

- Showing a visible error when a desktop action cannot start (the log line stays;
  visible feedback is a separate UX decision).
- The WeChat insertion failure that led to this being noticed (separate intent,
  linked above).
- Changing clipboard transaction semantics, delivery receipts, or history
  replacement rules.
- Cutting a release. The installed 0.0.60 stays broken until a later release;
  verification uses a development build.

## Constraints

- No dictated text in logs or diagnostics.
- `RestoreSelectionEditJob` (started with `input: .text("")`) and the voice
  `.unselected` -> `.local` binding keep their current behavior.
- Empty or whitespace-only copy text must still refuse to start.
- Swift 6 / `.swiftLanguageMode(.v5)`, files under 300 lines, strings through `L(...)`.

## Acceptance criteria

- A test starts `SessionIntent(input: .unselected, operation: .copy("..."))` on a
  real `SessionDriver` with the production `VoiceWorkflowFactory` and ends with
  `deliveryStatus == .copied`, the pasteboard holding the exact text, and no
  history record or output-anchor change. It fails on `0e0f3c1` with
  `invalidSessionState` and passes after the fix.
- A test starts `SessionIntent(input: .unselected, operation: .applyReplacement(id))`
  the same way and ends in the same outcome as the existing `.local` test for
  that operation (replacement applied or clipboard fallback).
- A test (or deterministic check) proves that `NativeDesktopHost.copy` and
  `applyReplacement` hand the execution service exactly the intents the tests
  above use.
- Whitespace-only copy still refuses to start; dictation started with
  `.unselected` still binds `.local`; `.restoreSelectionEdit` is unchanged.
- On a development build, clicking Copy in the overlay, the menu bar popover,
  and History changes the system pasteboard to the shown text, and the unified
  log has no `Desktop action could not start` entry for those clicks.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and
  `swift test` pass.

## Open questions

1. Where the fix belongs (non-capturing jobs accept the binding, or the host
   stops sending `.unselected` for them) is a design choice for the spec; either
   must satisfy every criterion above.
2. Whether this ships as its own patch release or rides with the next one.
