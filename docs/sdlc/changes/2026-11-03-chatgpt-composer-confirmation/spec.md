# Spec: Confirm a paste into an empty-looking web editor whose placeholder disappears

**Status:** approved
**Approved-by:** User, chat answer "批准" (22:35 UTC+8) to the compound question "是否批准 spec 和 plan，以及是否含 D5". The reply did not say 含/不含; the spec's stated default (include D5) is applied and is open to reversal at review. PR, merge, tag and release remain separate decisions
**Approved-date:** 2026-11-03
**Upstream:** [intent](intent.md) (approved 2026-11-03)
**Risk lane:** High, as in the intent.

## Measurements (Batch 0, done 2026-11-03 22:18–22:23 UTC+8, Utter 0.0.62)

Method: a passive watcher (`evidence/batch0-ax-shape-watcher.swift`) reads the focused field of the frontmost target app
every ~120 ms and prints character counts by class, never text; consecutive values of the same editable field are
compared (common prefix and suffix, removed and inserted counts). It writes nothing. Raw shape lines and the matching
delivery and history rows are in `evidence/batch0-shapes.txt`.

| Case | Field before | Field after paste | Utter result |
|---|---|---|---|
| ChatGPT app, **empty** composer, 103-unit text and, in a second run, 34-unit text (2 of 2) | 12 units (10 ASCII, 1 space, 1 LF at the end; first unit a letter, last a line feed), caret 0,0, `AXPlaceholderValue` none | **Exactly the text** (103 and 34 units). prefix 0, suffix 0, the 12 units are gone, no trailing LF | `uncertain` (3 s timeout), both times |
| ChatGPT app, text before the caret (103 units), caret at the end, 43-unit text | 103 units | 146 units: the old value plus the text (prefix 103) | `accepted` |
| T3 Code, empty composer, 22 and 115-unit texts | `"\n"` with an `AXPlaceholderValue` of 43 units, caret 0,0 | exactly the text | `accepted` (the existing `"\n"` rule) |
| T3 Code, 10 units before the caret, 11-unit value, 41-unit text | 11 units | 53 units: prefix 10, the 11th unit is gone, 43 units inserted that start with a line feed | `uncertain` |

Conclusions the design rests on:

1. **ChatGPT keeps its placeholder inside the value** (not in `AXPlaceholderValue`) and removes it as soon as text is
   inserted. After the paste the field equals the replacement exactly. Today's expectation (`document` with the text at
   the caret = placeholder plus text appended) never matches, which explains 5 of 5 `uncertain` records for an empty
   composer. The placeholder text was not read; "placeholder" is the best explanation of a 12-unit value that vanishes on
   insert, not a proven label.
2. **The same exact-equality shape is already trusted for T3 and Cursor** (`"\n"` becomes the text), so accepting
   "the field now holds exactly the replacement" for an empty-looking field extends a measured rule, it does not create a
   new kind of rule.
3. **A second, different cause exists** for `uncertain` with text before the caret (T3 row 4 and the earlier records):
   the unit after the caret is replaced, and the inserted segment is longer than the history text. One sample is not
   enough to design a rule from. This spec does not guess it (D5).
4. **Not measured:** caret in the middle of ChatGPT text, multi-paragraph replacements, ChatGPT in a Chromium browser tab.

## Design

### D1. Accept a second value for an empty-looking field

`DeliveryExpectation` returns the **set of values the field may hold when the text landed** instead of one value.

- Always: today's computation (`document` with `replacement` at `range`). For native targets this is the only value;
  behavior is unchanged.
- Additionally, only when **all** hold: the target is a web content editor, `range == (0, 0)`, `replacement` is not
  empty, and `replacement != document`: the value `replacement` itself.
- The existing `"\n"` rule stays as it is: for a lone `"\n"` document the set is exactly `[replacement]`.

Why a second candidate and not "recognize the placeholder": a real draft such as `"abc\n"` with the caret at the start
has the same shape as a placeholder plus line feed. Recognizing placeholders would wrongly expect `replacement` for it.
The second candidate needs no recognition: with a draft `"abc\n"` it simply never matches, and the first candidate
still does.

### D2. Why this cannot confirm a paste that did not land

- A candidate equal to the original document is never accepted (kept from today: an unchanged field proves nothing).
- Every accepted value contains the whole replacement. An empty replacement (delete flows) gets only the normal value.
- For the extra candidate to be observed, the field must have changed from its pre-paste value to exactly the text.
  Nothing except the text arriving can do that; a draft that exists before the paste cannot equal the replacement unless
  it already did, and that case is excluded by `replacement != document`.
- The wait, the 3 s timeout and the single-write rule are untouched: confirmation never writes.

### D3. Anchors

`NativeDeliveryTarget.insertionAnchor` today demands `value == expectedDocument`. It will accept any value of the set.
The anchor range is `[range.location, replacement length]` in both cases (location is 0 for the extra candidate), so
follow-up replace and undo address the same characters.

### D4. Observation API

`DeliveryTextObservation.confirm` takes the set (`accepting: Set<String>` or a predicate) instead of one string; the
polling, deadline and cancellation behavior are unchanged. Returns `true` on the first read that is in the set.

### D5. A counts-only diagnostic for the cause this spec does not fix (owner decision)

When confirmation times out, log one line with counts only: units of the last observed value and of the expected
value, common prefix and suffix lengths between them, line-feed and no-break-space counts, and whether the last
observed value equals the original document. No text, no hashes. This turns the next `uncertain` into evidence for the
second cause. It is a read-only logging addition and can be dropped without affecting D1 to D4.
Recommendation: include it. **Decision (2026-11-03): included**, by the spec's default after the owner's bare "批准".

### D6. Kill switch and rollback

No new switch. The rule only applies to targets classified as web content editors, so the existing hidden switch
`deliveryWebEditorPasteDisabled` already turns it off together with the whole web path. Rollback is reverting the
change: the previous behavior is the `uncertain` notice on every empty ChatGPT composer; there is no data migration.

## Test plan

Unit (pure, in `UtterMacServicesTests`):

- The measured shapes: empty ChatGPT shape (12 units, LF last) with caret 0,0 → the set contains the text; the observed
  value equal to the text is accepted; the observed value equal to the original document is not.
- `"\n"` document: set is exactly the text (unchanged); caret not at 0, non-empty selection, empty replacement, native
  target: no extra candidate.
- A draft `"abc\n"` with the caret at 0 and a web editor: observed `text + "abc\n"` accepted, observed `text` accepted
  by rule, observed `"abc\n"` rejected, observed `"abc"` rejected.
- `replacement == document` adds nothing.
- Observation with a fake clock: a value that becomes the text after 2 s confirms; a value that stays the original
  times out; a value that becomes something else times out.
- Anchor: accepted with either value, wrong value rejected.
- Mutation check: remove the extra candidate and the new tests fail; widen it (drop `replacement != document`, drop
  the `(0, 0)` guard) and the negative tests fail.

Hardware (Batch 3, independent verifier, release-style build, this machine):

- 10 dictations into an empty ChatGPT composer, 10 at the end of existing text, 5 in the middle: each ends `accepted`,
  text once. Evidence: the watcher's shape lines, the unified log, history rows.
- Cursor, T3 Code, Dia fields and TextEdit/Notes: one run each, unchanged results.
- A forced non-landing case: dictate while the composer loses focus or is read-only, and show `uncertain`.
- Not covered unless the verifier runs them: multi-paragraph text in ChatGPT, ChatGPT in a browser tab. They are listed
  in `verification.md` as unverified if skipped.

## Risks

| Risk | Handling |
|---|---|
| A field that holds exactly the replacement without the paste having landed | Excluded by the candidate rules in D2; negative unit tests and mutation check |
| The second cause stays | Stated, measured with D5, follow-up intent if it needs its own rule |
| ChatGPT changes its placeholder behavior | The first candidate still works; the worst case is today's `uncertain` |
| Anchor created for the wrong range | D3 uses the same range for both candidates; unit test |

## Out of scope

The second cause itself, a retry or second write, the timeout, the compact notice, native targets, any change to
`AXSelectedText` or paste behavior.
