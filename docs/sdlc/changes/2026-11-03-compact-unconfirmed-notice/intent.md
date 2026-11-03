# Intent: The "insertion unconfirmed" notice must be compact and leave on its own

**Status:** approved
**Approved-by:** User, answered the approval question in this conversation: design A (compact, self-dismissing notice, 8 s), and approve intent, spec and plan together. PR, merge, tag and release remain separate decisions
**Approved-date:** 2026-11-03
**Upstream:** — (related, not modified: [Dictated text must land in web content editors](../2026-10-25-electron-delivery-uncertain/intent.md))
**Risk lane:** Medium. User-visible UI and its dwell behavior. No change to text delivery, delivery receipts, history, permissions, privacy, signing, or the release pipeline. The release that ships it follows `release-runbook.md` and its own gate.

## Problem

After dictation, the HUD sometimes shows "无法确认是否已写入。可以复制文本，Utter 不会自动再次写入。" with Copy and Close
buttons. The owner reports that it appears often during normal use, that it is not needed in most of those cases,
and that it looks bad.

### Evidence (2026-11-03, installed Utter 0.0.61, `origin/main` at `3748367`)

- **How often.** Input history (`input_history.json`; only delivery status, app name and timestamps were read, no text):
  of 103 records since 2026-10-31, 11 ended `uncertain` (about 11%): ChatGPT 4 of 5, T3 Code 6 of 92, Dia 1 of 1.
  The desktop apps that dominate daily use end `inserted` most of the time, so the notice is occasional but never
  predictable.
- **It stays until clicked.** `SessionPresentation.keepsVisible` is true for `uncertain`, and
  `NativeDesktopHost.project` only schedules a hide for non-`keepsVisible` states (1.5 s). The notice therefore stays on
  screen across later work until the user clicks Close. In the owner's screenshot the notice is over Cursor while the
  history shows the previous dictation (15:06, T3 Code) ended `uncertain` and the next one (15:07, Cursor) `inserted`.
- **Why `uncertain` happens.** `NativeDeliveryTarget.confirm` returns false when the target's text value cannot be read
  back or does not equal the expected document after the paste. For a target that exposes no readable value it is
  false immediately, even if the paste landed. The state is truthful ("cannot know") but the UI treats it like a
  failure that needs acknowledgement.
- **Layout.** The `.error`/`.uncertain` HUD is a fixed 360 × 96 card. The status row and a second row of buttons are
  stacked, Copy is pinned to the left edge and Close to the right edge with a wide empty gap, and the buttons use the
  system bordered style, which looks like grey slabs on the dark glass. The render test shows the short
  `delivery.uncertain` string, not the long message production produces, so the test does not cover the real case.
  Baseline renders: `evidence/before-*.png` in this bundle.

## Outcome

- When insertion cannot be confirmed, Utter shows a compact one-row notice that carries the same facts (could not
  confirm, text can be copied, no automatic second insertion) and leaves on its own after a few seconds.
- The notice never needs to be dismissed by hand to get it out of the way, and a later dictation replaces it at once.
- The truth is unchanged: the delivery stays `uncertain`, history records it, the menu bar icon keeps its state, and
  Copy still works while the notice is shown or after reopening it from the menu bar.
- Error notices that need action (models, permissions, clipboard disabled) get the same cleaner layout and stay until
  closed.

## Scope

In scope:

- Layout and styling of the `.error` / `.uncertain` HUD, in dark and light system appearance, Chinese and English.
- A bounded dwell for `uncertain` only.
- Tests: layout, dwell policy, host behavior, and a render test that uses the production message.

Non-goals (stated so the approver knows what this does not fix):

- **The root cause of unverifiable deliveries** (targets whose text cannot be read back, e.g. ChatGPT). Fixing or
  silencing those needs a delivery-layer design (high-risk lane: it changes the core output path). This change makes
  them cheaper to see, not rarer. A follow-up intent is proposed in the verification record.
- Removing the `uncertain` state, the history field, or the menu bar indicator.
- Changing delivery, clipboard, receipt, or confirmation logic or timeouts.
- Changing the recording, processing, copied, or done HUDs.
- New settings or permissions.

## Constraints

- No dictated text in logs or diagnostics.
- All user-facing strings through `L(...)` with both `en.lproj` and `zh-Hans.lproj` entries.
- Files stay under 300 lines; Swift 6 with `.swiftLanguageMode(.v5)`.
- Respect Reduce Motion and Reduce Transparency as the HUD already does; icon-only controls keep accessibility labels.

## Acceptance criteria

- With the production message, the `uncertain` HUD renders in light and dark windows, in Chinese and English, with the
  status icon, the full message (not clipped), a Copy button and a Close button on a single row, and a height below
  the current 96 pt. Render evidence is attached.
- `.error` HUDs for models, permissions and clipboard-disabled render with the new layout, their action button, and
  an unclipped message in Chinese and English.
- A host test with a fake overlay shows: after a session ends `uncertain`, the overlay is hidden after the dwell; a
  new session started before then keeps the overlay (new content) and is not hidden by the old timer; an `.error`
  session is not auto-hidden; the existing 1.5 s behavior for `done`/`copied` is unchanged.
- After the notice has left on its own, clicking the menu bar icon while the phase is still `uncertain` shows it again
  and it again leaves after the dwell.
- Copy still copies the dictated text and Close still hides the notice (tests or real-window run).
- `SessionPresentation` for `uncertain` still reports `keepsVisible == true` and `canCopy` as today; history still
  records `uncertain`; the menu bar phase is unchanged (existing tests pass unchanged).
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and `swift test` pass.

## Open questions

1. **How much to hide.** (**Resolved 2026-11-03: option A, the compact self-dismissing notice.**) The proposed answer was the compact, self-dismissing notice. The alternative is no HUD at all
   for `uncertain` (menu bar icon and history only). That removes the cue for the cases where text really did not land,
   so it is not proposed without the owner's explicit choice. See the spec, D2.
2. **Dwell length.** The spec proposes 8 s. It can be changed in one constant.
