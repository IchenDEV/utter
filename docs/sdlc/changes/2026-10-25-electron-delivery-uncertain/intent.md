# Intent: Dictated text must land in web content editors (Electron apps and Chromium browsers), not end "uncertain" with nothing inserted

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Previously approved:** User, 都批准, 2026-10-25 00:18 UTC+8, for the narrower scope "Electron/Chromium chat inputs". Reopened on 2026-10-25 14:18 UTC+8 because the user reported a wider scope; see "Revision 2026-10-25 (scope widened)" below.
(The directory name keeps the original slug so existing links stay valid.)
**Upstream:** [Stop the Xiaomi remote's voice key from triggering macOS Dictation](../2026-10-24-swallow-remote-dictation-key/intent.md) (this problem was first suspected to be a side effect of that one, then separated by evidence)

**Risk lane:** High — it changes the core text-output path that writes into other apps for every user; a wrong fix can insert text twice, clobber the clipboard, or insert into the wrong field. The full bundle, an independent verifier, and an explicit rollback are required.

## Problem

After dictating into the Cursor agent chat input, the user sees no text appear. Utter's log for the latest case (2026-10-24 23:58:29, installed Utter 0.0.57) shows transcription and polishing succeeded, then `Delivery completed: uncertain, confirmation: none` about 3.0 s after the polished text was ready. The same outcome recurs across the session; it is the second failure the user reported.

### Evidence (2026-10-24)

- **Not the remote.** After the remote's voice key was neutralized (device-level F5 remap, stray text gone), dictation into Cursor still ends `uncertain`. The input history records the trigger as `menuBar`. The earlier suspicion that macOS Dictation holding the field open caused it is **falsified**.
- **Where it fails.** Input history contexts for recent dictations are Cursor (`com.todesktop.230313mzl4w4u92`, window "Cursor Agents") and T3 Code (Nightly), both Electron apps. The latest failure is Cursor.
- **What Cursor's input exposes** (read-only AX probe, frontmost app, no writes): role `AXTextArea`; `AXValue` is a string of length 1 although the field looks empty; selection 0,0; `AXSelectedText` and `AXValue` are both reported **settable**.
- **What the code does** with such a target: `NativeDeliveryTarget.supportsSelectionWrite` is true, so `TextDeliveryTransaction` writes the text through the AX selected-text attribute, marks a document effect, then waits for the field's AX value to reflect the change. The wait times out after about 3 s, the result is `uncertain`, and no clipboard-paste fallback runs after an effect was marked.
- **Timing.** The 3.02 s gap between "polish done" and "delivery completed" matches the confirmation timeout, not an immediate AX error.

### Inferred, not yet proven

- The AX write returns success but the web editor ignores it, so nothing is inserted. This is consistent with the timing and the user's report but needs a controlled probe. (**Proven in the spec stage; see the spec's evidence table.**)
- Whether this is a regression (delivery confirmation was introduced on 2026-10-04) or a change in Cursor's editor, and which other Electron apps share it.

## Outcome

Dictating into web content editors inserts the text once, and delivery reports `accepted` when the text really landed. This covers Electron app inputs (Cursor, T3 Code and other Electron apps) and text fields on web pages in Chromium-based browsers. Native fields keep their current behavior.

## Scope

Affected: users who dictate into web content editors. Observed in logs: Cursor and T3 Code. Reported by the user on 2026-10-25 (no log evidence yet): text fields on web pages in browsers and inputs in other Electron apps, with the symptom "no text appears at all".

In scope:

- Establish with a controlled probe what the AX write and paste each do in these targets.
- Make delivery reach the field and report truthfully.
- Keep the existing safety property that an unconfirmed attempt is never retried blindly.
- Measure whether non-Chromium browsers (Safari/WebKit) behave the same way. A rule for them ships only on measured evidence and only after the user approves it.

Non-goals:

- Removing delivery confirmation or the `uncertain` state.
- Changing native `NSTextView`/`NSTextField` behavior when it already works.
- The remote's F5 handling (separate change).
- Changing ASR, polishing, or prompts.
- Targets the user did not report (native fields, WeChat, other custom text views). They are revisited only if reported or if measurement shows the same failure.

## Constraints

- Never insert the same text twice; a fallback may run only when the first attempt is known not to have taken effect.
- Preserve the clipboard transaction behavior and the "clipboard delivery disabled" setting.
- No dictated text in logs or diagnostics; counts, timings, and role/capability facts only.
- No new permission or entitlement.
- Do not special-case by hard-coded app name unless the spec shows capability detection cannot work, and then keep the list small and testable.

## Acceptance criteria

- On the reproducing machine, 10 consecutive dictations into the Cursor agent input insert the text exactly once and end `accepted`.
- The same in T3 Code (Nightly).
- In a Chromium-based browser (Dia on the reproducing machine), 10 consecutive dictations into each of a single-line `<input>`, a `<textarea>`, and a `contenteditable` field on a test page insert the text exactly once and end `accepted`.
- The same in one more Electron app (Feishu is installed on the reproducing machine); if its field differs, the difference is recorded and returned to the spec.
- Chromium browser UI fields (address bar, find bar) still receive dictated text exactly once.
- Safari (WebKit) is measured with the same protocol. The result is recorded; any rule for it needs an approved spec revision.
- Native targets (TextEdit, Notes) still end `accepted` with no extra clipboard writes beyond today's.
- A controlled test shows that a write which has no effect is distinguished from one that took effect, and that no path inserts twice.
- With clipboard delivery disabled, behavior is unchanged and does not insert twice.
- Delivery results and timings are logged without text; the existing `uncertain` state still appears when the outcome truly cannot be known.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and `swift test` pass.

## Open questions

1. **Detection versus fallback.** Detect an ineffective AX write (value unchanged shortly after a successful write) and then paste, or choose paste up front for targets whose role/capabilities look like web editors? Decide in the spec from probe results. (**Resolved in the approved spec: classify up front.**)
2. **Does paste confirm in these editors?** If Chromium's AX value updates after paste, confirmation works; if not, `accepted` may be unreachable and the acceptance criteria need a different proof. (**Resolved in the approved spec: yes in Cursor, with placeholder-aware confirmation.**)
3. **Which apps.** Capability-based detection should cover Cursor and T3 Code; other apps (VS Code, Slack, browsers) need a decision on how far to verify. (**Partly answered 2026-10-25:** the user reports browsers and other Electron apps; the scope above covers Chromium-based ones by the same capability. Which browser the user means, and whether Safari is affected, is still unknown; Safari is measured, not assumed.)
4. **Regression window.** Is this new since 2026-10-04 or since a Cursor update? Affects whether a quick revert path exists.

## Revision 2026-10-25 (scope widened, 14:18 UTC+8)

- **What changed:** after reading the plan summary the user said the problem is "not only Electron/Chromium input boxes". Asked which apps and which symptom, the user chose "browser web input fields" and "other Electron-type apps" (Cherry Studio, Grok Bot, Manus and similar), with the symptom "no text appears at all", and told the agent to revise the spec directly. The title, outcome, scope, non-goals, acceptance criteria and open question 3 above were updated; constraints are unchanged.
- **What the data can and cannot say:** input history has delivery status for only 9 of 500 records (the field was added recently): 7 `uncertain` (6 Cursor, 1 T3 Code), 1 `inserted` (Finder), 1 `notDelivered` (System Settings). The other 491 records, including 18 from Dia, 30 from WeChat and 111 from ChatGPT, have no status, so the history neither confirms nor denies failures in browsers or other apps. The widening rests on the user's report, not on logs.
- **Read-only probe 2026-10-25 14:2x (no writes, no text read):** T3 Code's focused input is identical to Cursor's (see the spec's evidence). Dia exposes `ChromeAXNodeId` on its elements, so Chromium browsers share the signature; no web text field was focused, so browser write behavior is not yet measured. Safari was not running.
- **Not covered:** the user did not report native fields or WeChat; they stay out of scope unless reported.
- **Process:** the three artifacts (intent, spec, plan) return to `pending approval`; nothing else is implemented. Approval of this revision is the user's.
