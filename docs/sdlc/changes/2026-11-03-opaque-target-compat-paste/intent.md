# Intent: A compatibility switch so dictation still reaches input boxes Utter cannot inspect

**Status:** approved
**Approved-by:** User, chat answer "批准" (22:35 UTC+8) to the question that named this intent, its High lane and the recommendations in open questions 1 and 3 (default off; quiet HUD with `uncertain` kept in history). Those two recommendations are treated as adopted; they can be reversed in the spec review. Open questions 2, 4 and 5 stay open for the spec. Spec, plan, PR, merge and release remain separate decisions
**Approved-date:** 2026-11-03
**Upstream:** [Confirm text delivery](../2026-10-25-electron-delivery-uncertain/intent.md) (the delivery receipts and the "never write twice" rule this change must keep), [ChatGPT composer confirmation](../2026-11-03-chatgpt-composer-confirmation/intent.md) (separate problem, separate bundle: it fixes false "unconfirmed" notices where the text did land)
**Risk lane:** High. It adds a new way for Utter to write into another app, on the core output path, for targets whose content Utter cannot check. A wrong design can paste into the wrong place or into a sensitive field. Independent verifier, explicit rollback and the owner's merge authorization apply.

## Problem

The owner reports (2026-11-03) that the input experience is less stable than earlier versions and "often nothing goes in", and asked for a **compatibility switch** in Settings.

### Evidence

- **WeChat never receives the text.** Input history records delivery status only since late October. For WeChat all 4 records with a status (2026-10-30 and three on 2026-11-03) are `notDelivered`. The HUD says "写入目标已变化。可以复制文本，或重新开始。" although nothing changed. Before delivery receipts existed (2026-10-13 to 2026-10-23) WeChat had 13 records with no status, so their outcome is unknown.
- **Why, from the code.** `NativeDeliveryTarget` is built only when the frontmost app answers the Accessibility query "focused UI element". If it does not, the init returns nil, `NativeOutputBackend.deliver` returns `notCommitted` with `delivery.target_changed`, and nothing is pasted or copied. `NativeTargetLease.isCurrent` also requires a focused element, so no later step could write either.
- **A measurement agrees, once.** A passive probe (shape only, no writes) saw the WeChat app frontmost at 22:33 UTC+8 with `AXFocusedUIElement` unavailable ("no focused element"). One sample; the probe is still running for more.
- **The change that introduced this is known, the behavior of the earlier version is not measured.** The commit "Confirm text delivery and preserve clipboard transactions" (2026-10-04) made delivery require a verifiable target. Whether earlier builds pasted into WeChat successfully was not tested.
- **Other apps with the same shape are unmeasured.** Feishu, QQ and other custom-drawn inputs are installed on the owner's machine; none has a delivery record.

## Outcome

With the switch on, dictating into an app whose input box Utter cannot inspect pastes the text once into the app that was frontmost when recording started. Utter is honest that it could not verify the result. With the switch off, nothing changes except that the message for this case stops claiming the target "changed".

## Scope

In scope:

- A Settings toggle (name, default and exact semantics are decided in the spec) next to the existing clipboard-paste option, with a help line that says what it risks.
- A paste path used only when the focused element cannot be read (the case above), reusing the existing clipboard transaction and its rules.
- A truthful result for that path (the delivery cannot be `inserted`) and a presentation that does not show the long "unconfirmed" notice on every dictation (options in the spec).
- A clearer message for the switch-off case: "this app does not allow direct writing; turn on compatibility mode", in English and Chinese.
- Measuring WeChat and at least one more opaque app (QQ or Feishu) before writing the spec.

Non-goals:

- Making the text land in places that reject paste.
- Changing targets that expose a focused element, including the ChatGPT confirmation fix (its own bundle).
- Retrying a paste, or pasting twice for any reason.
- Reading or logging the content of the other app's field.

## Constraints

- Never paste while secure input is active, when the frontmost app is no longer the one captured at the start of the session, when the lease is revoked, or when "allow clipboard paste" is off.
- Exactly one paste attempt per delivery. After the attempt there is no retry and the clipboard is not restored until a confirmation exists (existing rule), so the dictated text stays on the clipboard; the help text must say so.
- No dictated text or field content in logs. Counts, timings and path names only.
- No new permission. No app-name special case unless the spec shows the capability test cannot work, and then a short list.
- `swift test`, `bash scripts/ci-basic-checks.sh`, `bash scripts/sdlc-checks.sh` pass.

## Acceptance criteria

1. **WeChat, switch on.** 10 consecutive dictations into a WeChat chat input each insert the text exactly once (checked by eye and by a read-only before/after screenshot or paste-back), and each ends with a truthful status (not `inserted`) and no long notice (per the spec's presentation choice).
2. **A second opaque app** (QQ or Feishu, the one that actually exposes no focused element) behaves the same, or the difference is recorded and returned to the spec.
3. **Switch off.** WeChat dictation still ends `notDelivered`, writes nothing, and shows the new clear message. Targets with a focused element behave exactly as today (existing tests plus one run each in T3 Code, Cursor and ChatGPT).
4. **Guards.** Unit tests prove no paste happens with secure input on, with a changed frontmost app, with a revoked lease, with clipboard paste disabled, and that exactly one paste is posted per delivery.
5. **Truth.** The status recorded for the compatibility path is never `inserted` and never `accepted` with a target-value confirmation.
6. **No text in diagnostics.** Log lines added or changed contain no dictated or field text.
7. The standard checks above pass.

## Open questions for the spec

1. Default: on or off? (Recommendation: off for the first release, so the new write path is opt-in; the owner turns it on.)
2. Scope: only when no focused element exists (recommended, measured), or also when an element exists but its text is unreadable (that path already pastes and ends `uncertain`).
3. Presentation: keep `uncertain` and the compact notice every time, or keep `uncertain` in history but show the normal quiet "done" HUD for opted-in opaque targets, or a new status. (Recommendation: the second; the owner opted in knowing it cannot verify.)
4. Setting name and wording, and whether it lives in General → Output or under advanced options.
5. Which opaque apps the acceptance run must cover beyond WeChat.

## Request to the owner (no code is written before approval)

Approve or change this intent, in particular the High lane and the recommendations in open questions 1 and 3. While you wait, using WeChat normally helps: the probe records, shape only, whether it exposes a focused element when you dictate there.
