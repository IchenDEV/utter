# Intent: Dictation into the ChatGPT composer must be confirmed when the text really landed

**Status:** approved
**Approved-by:** User, chat answer "批准" to "是否批准 intent 草稿（风险档可改成中等）", 2026-11-03 22:13 UTC+8; the risk lane stays High because the owner did not downgrade it. Spec, plan, PR, merge and release remain separate decisions
**Approved-date:** 2026-11-03
**Upstream:** [Compact unconfirmed notice](../2026-11-03-compact-unconfirmed-notice/intent.md) (made the notice smaller; its non-goal named this root cause), [Dictated text must land in web content editors](../2026-10-25-electron-delivery-uncertain/intent.md) (introduced `isWebContentEditor` and the placeholder-aware expectation this change extends)
**Risk lane:** High. It changes how the core output path decides `accepted` versus `uncertain`. Confirmation never writes, so a wrong expectation cannot insert twice, but a too-loose one can report `accepted` for text that did not land, and `accepted` creates the insertion anchor that follow-up edits and undo rely on. Independent verifier, explicit rollback and the owner's merge authorization apply. The owner may downgrade the lane; that is their decision.

## Problem

The owner reports (2026-11-03, installed Utter 0.0.62, after the compact notice shipped): the dictated text **was** inserted into the ChatGPT composer, and Utter still shows "无法确认是否已写入". The new notice looks much better, but it should not appear when the insertion succeeded.

### Evidence

- **Path and target.** Unified log, 21:56–21:59 (UTC+8) today, Utter 0.0.62: every delivery in the window is `path: paste, target: web`. Three in a row end `uncertain, confirmation: none`, then three end `accepted, confirmation: targetValue`. So paste into a Chromium web editor confirms sometimes and not other times.
- **It follows the composer's state.** Input history (delivery status, app name, timestamp and the presence of text before the caret only; no dictated text was printed): in ChatGPT, dictations into an **empty** composer (no text before the caret) ended `uncertain` 5 of 5 (2026-11-02 and 2026-11-03). With text before the caret: 2 `inserted`, 2 `uncertain`. Cursor shows the same pattern before 2026-10-25 and `inserted` after the placeholder fix of the earlier bundle; T3 Code ends `inserted` in 170 of 180 records.
- **What ChatGPT's empty composer reports** (read-only Accessibility probe of the focused element while ChatGPT was frontmost, shape only, 22:01 UTC+8): role `AXTextArea`, carries `ChromeAXNodeId`, `AXSelectedText` settable, selection `0,0`, and an `AXValue` of 12 UTF-16 units made of 10 ASCII characters, 1 space and 1 line feed that ends the value. That is not the lone `"\n"` that `DeliveryExpectation` knows how to expect. It is consistent with a placeholder string plus a trailing line feed, but the text was deliberately not printed, so this is **inferred, not proven**.
- **What the code does with it.** `DeliveryExpectation.expectedDocument` only drops the placeholder when the document is exactly `"\n"`. For any other empty-looking value it computes "document with the text inserted at the caret". If the editor removes the placeholder once text is inserted, the real value becomes the dictated text alone, never equals the expectation, and `DeliveryTextObservation.confirm` times out after 3 s as `uncertain`.
- **Not yet measured:** the value ChatGPT reports **after** a paste (whether a trailing line feed remains, how a non-empty composer reports its caret and trailing break), and the cause of the 2 `uncertain` records that had text before the caret.

## Outcome

- When the text really landed in the ChatGPT composer, delivery ends `accepted` with `confirmation: targetValue`, in an empty composer and in a composer that already has text, and the notice does not appear.
- A paste that did not land, or that landed somewhere else, still ends `uncertain`. No path writes twice.

## Scope

In scope:

- Measure, read-only and shape-only, what the ChatGPT composer reports before and after a real Utter dictation (empty composer; composer with text, caret at the end, in the middle).
- Make the expected value for web content editors match what was measured, and nothing wider.
- Tests built from the measured shapes, including the negative cases below.

Non-goals:

- Removing the confirmation, the `uncertain` state, the 3 s timeout, or the compact notice from the previous change.
- Targets other than web content editors. Native fields keep their behavior.
- Making `uncertain` impossible for targets that expose no readable value; they stay `uncertain` because that is true.
- Logging dictated text or editor text. Diagnostics, if added, carry counts and flags only.

## Constraints

- Confirmation must not become a blanket "accept anything": the observed value has to equal a value that can only exist if the text landed.
- Never insert twice; no new write, retry or clipboard behavior.
- No new permission. No app-name special case unless the spec shows the capability signature cannot work, and then a short, testable list.
- `swift test`, `bash scripts/ci-basic-checks.sh`, `bash scripts/sdlc-checks.sh` pass.

## Acceptance criteria

1. **Empty composer.** On the reproducing machine, 10 consecutive dictations into an empty ChatGPT composer (clear it between runs) end `accepted` with `confirmation: targetValue`, the text appears once, and no unconfirmed notice shows. Recorded from the unified log and input history.
2. **Composer with text.** 10 dictations with the caret at the end of existing text, and 5 with the caret in the middle, end `accepted`, text once.
3. **No regression elsewhere.** Cursor, T3 Code and Dia web fields still end `accepted`; TextEdit/Notes behave as before (existing tests plus one run each).
4. **Truth preserved.** Unit tests show `uncertain` when the observed value equals the original document (the paste did nothing), when it contains other text than expected, and when the target cannot be read.
5. **No text in diagnostics.** Log lines added or changed contain no dictated or editor text.
6. The standard checks above pass.

## Open questions for the spec

1. The post-paste shape in ChatGPT, and whether it is the same in the desktop app and in a Chromium browser tab on chatgpt.com. Decided by the measurement in the first batch.
2. Whether the two `uncertain` records with text before the caret share this cause or have another one (for example a trailing line feed or whitespace normalization). Decided by the measurement.
3. How to express the rule: a second accepted candidate for a caret at the start of an empty-looking editor, or a recognized placeholder shape. The spec compares both against the false-accept risk above.

## Request to the owner (needed for the measurement, no code is written before approval)

A passive watcher is running on this machine until about 22:46 UTC+8. It reads only the focused field of the ChatGPT app and prints character counts by class, never text. To fill the "not yet measured" gap, dictate normally into the ChatGPT composer a few times: first into an empty composer, then with some text already in it. Nothing else is needed.
