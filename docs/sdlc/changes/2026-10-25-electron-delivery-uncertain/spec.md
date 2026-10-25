# Spec: Dictated text must land in web content editors (Electron apps and Chromium browsers)

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (intent、spec、plan 一起), 2026-10-25 18:50 UTC+8, covering D1 and D5 extended to Chromium browsers and all Electron apps, D6 (WebKit measured, not assumed), and the added test matrix; D2, D3 and D4 stand as previously approved
**Approved-date:** 2026-10-25
**Previously approved:** User, 批准, 2026-10-25 00:30 UTC+8, for the narrower scope (Chromium web-content editors, evidenced in Cursor). Reopened on 2026-10-25 because the intent's scope was widened. See "Revision 2026-10-25" at the end.
**Upstream:** [intent](intent.md) (revision 2026-10-25, approved 2026-10-25)

## Context

`NativeDeliveryTarget.supportsSelectionWrite` is true whenever the focused element exposes a string `AXValue`, a selection range, and a settable `AXSelectedText`. `TextDeliveryTransaction` then writes through `AXSelectedText`, marks a document effect, and waits up to 3 s for the field's `AXValue` to equal the expected document. After an effect is marked it never falls back to paste, because a blind retry could insert twice. If the write is ineffective the result is `uncertain, confirmation: none`, and the HUD tells the user the write could not be confirmed.

### Evidence (2026-10-25, Cursor agent chat input, installed Utter 0.0.57)

All probes ran against the real field with an empty draft; text content was never read.

| Probe | Result |
|---|---|
| AX attributes of the focused element | Role `AXTextArea`; Chromium-specific attributes `ChromeAXNodeId`, `AXDOMClassList`, `AXDOMIdentifier`, `AXEditableAncestor`, `AXHighestEditableAncestor`, text-marker attributes. `AXSelectedText` and `AXValue` reported settable. |
| **T1: AX selected-text write** (what Utter does) | The call returned success (`0`), `AXValue` stayed at length 1 for 4 s, and the user saw nothing appear. **The inference is confirmed: the write reports success and has no effect.** |
| **T2: clipboard paste (Cmd+V)** | `AXValue` contained the marker 0.05 s after posting; a screenshot taken 1.8 s later shows the text in the input. **Paste works and is observable.** The user did not notice it the first time because it stayed only about a second. |
| Empty-field value | `AXValue` of an empty field is a single `U+000A`. After the paste the value was exactly the 15-character marker; the trailing newline placeholder was gone. |
| Existing confirmation logic | `DeliveryTextObservation.confirm` requires exact equality with `document` with the replacement applied at the selection. For an empty Chromium field that is the text **plus** the placeholder newline, which the real field never shows, so even a landed paste would be reported `uncertain`. |
| Utter's own UI | A screenshot shows the HUD toast "can't confirm it was written; copy the text; Utter will not write again" with copy and close buttons. |

### Evidence added 2026-10-25 (read-only probe of running apps)

A throwaway probe (`/tmp/axprobe`, not in the repo) read the focused element of each running candidate app. It performed no writes and printed no text, only role, attribute names, settability, value length and selection.

| App (bundle) | Focused element at probe time | `ChromeAXNodeId` | `AXValue` / `AXSelectedText` | Meaning |
|---|---|---|---|---|
| T3 Code (Nightly) (`com.t3tools.t3code`) | `AXTextArea` | yes | length 1, exactly `"\n"`, settable / settable; selection 0,0 settable | Identical to Cursor. D1 covers it. |
| Dia (`company.thebrowser.dia`) | `AXRow` / `AXOutlineRow` (a sidebar row, not a text field) | yes | length 0, readonly / readonly | Chromium browsers carry the same signature and accessibility is already on in Dia. **No web text field was focused, so browser write behavior is not measured.** It also shows the signature appears on Chromium browser UI, not only on page content (see the false-positive row below). |
| Feishu, Grok Bot, ChatGPT, WeChat, Cursor | no focused element at probe time (`kAXErrorNoValue`) | not measured | not measured | These apps were not frontmost or had no input focused. Not measured. |
| Safari | not running | not measured | not measured | WebKit is unmeasured (D6). |

`AXEnhancedUserInterface` read `0` in every app and nothing was set by the probe, so these apps expose their accessibility tree without Utter or the probe enabling it. An app whose Chromium accessibility tree is off would not expose `ChromeAXNodeId`; that is the false-negative row below.

Input history for context (not proof): delivery status exists for only 9 of 500 records, so it cannot show failures in browsers or other apps. The widening to browsers and other Electron apps comes from the user's report ("no text appears at all"), which matches T1 (the AX write reports success and has no effect).

Not yet proven: behavior for multi-line payloads, for non-empty fields, for web page `<input>`, `<textarea>` and `contenteditable` fields in a Chromium browser (including whether their empty `AXValue` is `""` or `"\n"`), for browser UI fields (address bar, find bar), for Feishu and other Electron apps, and for Safari. Batch 0 and verification cover them.

## Design

### Decisions on the intent's open questions

| # | Question | Decision |
|---|---|---|
| D1 | Detection versus fallback | **Classify up front; do not fall back after the fact.** A focused element that exposes `ChromeAXNodeId` is a Chromium accessibility node. When it is an editable text target, treat it as a web content editor: skip the AX selected-text write and use the existing clipboard paste transaction. This covers Electron apps and Chromium-based browser pages alike; no app or browser is named. A post-hoc fallback after an unconfirmed write is rejected: a late-applying write would insert twice, which the intent forbids. `AXDOMClassList` alone is not used because WebKit also exposes it and WebKit behavior is not measured (D6). |
| D2 | Does paste confirm? | Yes in Cursor (0.05 s), provided the confirmation understands the empty-field placeholder (D3). Other Chromium apps are verified individually (T3 Code is an acceptance criterion). |
| D3 | Placeholder-aware confirmation | For a classified target whose pre-delivery document is exactly `"\n"` (an empty paragraph, measured), the expected document is the replacement text with no trailing newline. Otherwise the expected document is computed as today. Confirmation stays an exact comparison, not a "contains" check, so a field that changed in some other way is still `uncertain`. |
| D4 | Clipboard delivery disabled | When the user has disabled clipboard delivery and the target is classified, return `notCommitted` with the existing `delivery.unavailable` reason immediately. The AX write is known to be ineffective there, so attempting it only adds a 3 s wait and a misleading `uncertain`. Native targets keep today's AX path. |
| D5 | Other apps | Capability-based, not app-name-based: any Chromium web-content editor is covered, including Chromium browser pages (Dia observed) and Electron apps beyond Cursor and T3 Code. No app list is hard-coded. Each class is verified individually (Dia web `<input>`, `<textarea>`, `contenteditable`; one more Electron app) rather than assumed. |
| D6 | WebKit and other engines | **Not classified by this change.** Safari was not measured and `AXDOMClassList` is not a safe discriminator. Batch 0 measures an empty field on a test page in Safari with the same protocol as T1/T2. If WebKit shows the same ineffective write, a narrower signature is proposed in a further spec revision that returns to the user; no WebKit rule ships on assumption. Until then Safari keeps today's behavior. |

### Changes (all in `UtterMacServices`)

1. `NativeDeliveryTarget`: add `isWebContentEditor` (the focused element exposes `ChromeAXNodeId`; any lookup error means native). `supportsSelectionWrite` returns false for web content editors.
2. Pure `DeliveryExpectation` (new, small): computes the expected document including the placeholder rule in D3, so it is unit-testable without AX. `NativeDeliveryTarget.expectedDocument` delegates to it.
3. `TextDeliveryTransaction`: for a web content editor with `allowsClipboardPaste == false`, return `notCommitted` before any write. The paste path and its clipboard snapshot, restore, and ownership checks are unchanged.
4. Logging: `Delivery completed` gains `path` (`accessibility` | `paste` | `clipboardOnly`) and `target` (`web` | `native`) fields. No text is logged.
5. No new permission, setting, or string.

No change to the `uncertain` state, `ClipboardPasteTransaction`, the 3 s timeout, or native behavior.

## Safety and failure modes

| Failure | Behavior |
|---|---|
| Classification false negative (a web editor without `ChromeAXNodeId`: WebKit, Firefox, or an app whose Chromium accessibility tree is off) | Today's behavior: AX write, then `uncertain`. No regression, but also no fix; the user's "no text appears" symptom persists there until D6 or a follow-up covers it. Stated plainly so approval is informed. |
| Classification false positive | `ChromeAXNodeId` appears on any Chromium accessibility node, including Chromium browser UI (measured on a Dia sidebar row), not only on page content. A native non-Chromium field cannot be misclassified. A Chromium browser-UI field (address bar, find bar) would paste instead of using the AX write; that is the same safe paste path. Batch 5 checks that text lands exactly once there. |
| Double insertion | Impossible by construction: exactly one of the AX write and the paste runs for a given target, and an unconfirmed paste is never retried. |
| Wrong field | Unchanged: `isCurrent` checks on identity, value, and selection run before the paste and the confirmation. |
| Clipboard clobber | Unchanged transaction: snapshot, write, paste, restore after confirmation; if unconfirmed the clipboard keeps the dictated text so the user's "copy" action still works. |
| Placeholder rule misfires | Only when the classified target's document is exactly `"\n"`; any other document uses the normal computation. A wrong expectation can only produce `uncertain`, never an extra write. |
| Multi-line payloads | Chromium may turn newlines into separate paragraphs and change `AXValue` formatting. If a multi-line paste lands but cannot be confirmed, it ends `uncertain` (safe). Verification measures this; any normalization needed is a follow-up spec revision. |
| Secure input | Unchanged guard: no paste during secure input. |
| Privacy | Logs and diagnostics carry only role, path, target kind, disposition, and timings. |

## Test strategy

| Acceptance criterion | Check |
|---|---|
| 10 dictations in the Cursor agent input insert once and end `accepted` | Hardware on the reproducing machine, repeated by the independent verifier; the `Delivery completed` log shows `path=paste target=web accepted`. Text visible exactly once each time. |
| Same in T3 Code (Nightly) | Hardware, same protocol. If T3 Code lacks `ChromeAXNodeId` or its field differs, report and extend D1 by evidence. The 2026-10-25 probe already shows the same element shape as Cursor. |
| Chromium browser web fields | Hardware in Dia on a local test page with `<input>`, `<textarea>` and `contenteditable` fields: 10 dictations each insert once and end `accepted`. Batch 0 first records, per field type, the empty `AXValue` (so D3's placeholder rule is applied only where `"\n"` is measured) and T1/T2 results. |
| One more Electron app | Hardware in Feishu (installed) or another Electron app the user names; differences are recorded and returned to the spec. |
| Chromium browser UI fields | Hardware: address bar and find bar receive dictated text exactly once, no clipboard left behind after an `accepted` paste. |
| Safari (D6) | Batch 0 measurement only; outcome recorded in `verification.md`. Any rule needs a further approved revision. |
| Native targets unchanged | Hardware TextEdit and Notes still `accepted` via the AX path with no extra clipboard writes; existing `UtterMacServicesTests`. |
| No-effect write distinguished, no double insertion | The T1/T2 evidence above plus unit tests with a counting fake: a classified target never calls `writeSelection`, the paste runs exactly once, and an unconfirmed paste is not retried. |
| Placeholder handling | `DeliveryExpectation` unit tests: `"\n"` with selection 0,0; non-placeholder documents; empty document; surrogate-pair boundaries; native documents unaffected. |
| Clipboard disabled | Unit test: a classified target with clipboard delivery disabled returns `notCommitted` and writes neither AX nor clipboard. |
| Logging without text | Unit test on the log line fields; manual log inspection. |
| Multi-line and non-empty field | Hardware cases recorded in `verification.md` (not required to be `accepted`, but must not insert twice). |
| Repo checks | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`. |

High risk: the independent verifier is not the implementer, reruns the Cursor and T3 Code protocols, the native checks, the multi-line and non-empty cases, and the clipboard-disabled case, and records results in `verification.md`.

## Rollout and rollback

1. Ship in a normal release.
2. Runtime kill switch: hidden default `deliveryWebEditorPasteDisabled = true` restores the previous AX-first behavior without a new build.
3. Stop conditions: any double insertion, insertion into the wrong field (including a browser address bar or find bar), or a clipboard not restored after an `accepted` paste. Response: kill-switch guidance, then revert.
4. Full rollback: revert the commit. The previous behavior is the `uncertain` state; the HUD's copy button and a manual paste remain the user's workaround.

## Approval record (previous revision, superseded until the revision below is approved)

The user approved the earlier revision of this spec on 2026-10-25 (chat: 批准, covering the artifacts listed in the preceding review message), including D1 (Chromium web-content editors identified by `ChromeAXNodeId`; paste instead of AX write; no post-hoc fallback), D3 (placeholder-aware exact confirmation), D4 (clipboard-disabled web editors return `notCommitted` immediately), and D5 (capability-based, no app list).

## Revision 2026-10-25 (scope widened to browsers and other Electron apps)

- **What changed:** the title and scope; the evidence table (T3 Code matches Cursor; Dia carries `ChromeAXNodeId`; other apps and Safari unmeasured); D1 and D5 now state that Chromium browser pages and any Electron app are covered by the same `ChromeAXNodeId` signature; new D6 (Safari and other engines are measured in Batch 0, not assumed, and any rule needs a further approved revision); the false-negative and false-positive rows; and four new test rows. D2, D3 and D4 are unchanged. No design change in the code beyond what the original `Changes` list already says: the same classification now simply applies to browser pages too.
- **What is not decided by this revision:** whether Safari/WebKit gets a rule; whether non-Chromium targets such as WeChat are affected (not reported).
- **Known limit, stated for approval:** the fix does not reach targets without `ChromeAXNodeId`. If the user's "no text appears" cases include Safari or Firefox, they stay unfixed until D6 produces a measured, approved signature.

## Approval requested

Please decide the revision as a whole: D1 and D5 extended to Chromium browsers and all Electron apps by the same signature; D6 (WebKit measured in Batch 0, not assumed); the added test matrix. D2, D3 and D4 stand as previously approved. Then this spec can move to `approved`; the plan (now including a measurement batch) is approved separately.

## Erratum 2026-10-25 (proposed, pending approval)

**Status of this erratum:** pending approval. **Approved-by:** — **Approved-date:** —. The approved text above is unchanged; the code in Batches 1–4 behaves as described here either way. Source: [`verification.md`](verification.md), "Batch 0".

1. **The "Classification false positive" row is withdrawn as written.** It said Chromium browser UI carries `ChromeAXNodeId`, citing a Dia sidebar row. Measured in Dia, the **address bar and the find bar do not carry `ChromeAXNodeId`, and the AX selected-text write is effective there**, so they stay on the AX path. The sidebar row was not a text field. Remaining risk, unmeasured: other Chromium browsers may expose the id on their own UI fields. Batch 5 checks Dia only.
2. **Evidence table, Dia row:** add that web `<input>`, `<textarea>` and `contenteditable` fields carry `ChromeAXNodeId`, report an empty value of `""` (not `"\n"`), and ignore the AX write (returns success, no effect).
3. **D3 as implemented is narrower than written:** the placeholder rule applies only with the caret at `0,0` and a non-empty replacement. In Dia it never triggers because the empty value is `""`.
4. **Known limit to state for approval:** after a page reload, 27/27 pastes landed in Dia; in a single page session without reloading, pastes into `textarea` and `contenteditable` fields often did not land (cause unknown, measured with synthetic clicks while the user was away). If this reproduces with real dictation, the user sees `uncertain` for those dictations and acceptance criterion "10 consecutive dictations" is not met by this design alone.
5. **Implementation notes (no design change):** `isWebContentEditor` also requires a settable `AXSelectedText`; a fourth log value `path=keyPress` exists for delete flows.

Please approve or reject this erratum separately from the verification stage.
