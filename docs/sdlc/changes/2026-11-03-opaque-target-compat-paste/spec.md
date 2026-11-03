# Spec: A compatibility switch for input boxes Utter cannot inspect

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [intent](intent.md) (approved 2026-11-03)
**Risk lane:** High, as in the intent.

## Measured facts this design rests on

| Fact | Evidence |
|---|---|
| WeChat exposes no focused UI element while it is frontmost. 7 of 7 samples, several only seconds apart. | `evidence/batch0-wechat-focus.txt` (read-only probe, shape only) |
| For WeChat every record with a status is `notDelivered` (4 of 4), and the HUD says "写入目标已变化" although nothing changed. | Input history, recorded in the intent |
| The lease for a local dictation is captured at session start with `AXTargetState.capture()` = nil in that case, so `NativeTargetLease.state` is nil and `isCurrent` is always false (it requires a focused element). `NativeDeliveryTarget.init` then returns nil and `deliver` returns `notCommitted` before anything is written or copied. | `NativeTargetLease.swift`, `NativeDeliveryTarget.swift`, `NativeOutputBackend.swift` |
| **Not measured yet:** whether a posted ⌘V lands in WeChat's input box when there is no focused element. The whole feature depends on it, so it is the first hardware step (plan item H0) with a stop rule. | none |
| **Not measured yet:** whether Feishu and QQ expose a focused element. A passive probe is running (`/tmp/axprobe/watch-opaque2.log`); the result is added to `evidence/` before implementation reaches those apps. | none |

## Decisions

**D1 — Default off.** A new setting `allowOpaqueTargetPaste` (default `false`). Off means no new write path exists.

**D2 — Scope: only when there is no focused element.** The compatibility path runs only for `DeliveryCommand.insert`
(never replace, delete, undo or restore) when all of these hold at the moment of writing:

1. the setting is on and `allowClipboardPaste` is on (the new setting is disabled in the UI while the old one is off);
2. `AXIsProcessTrusted()` is true, so "no focused element" describes the app, not a missing permission;
3. the lease was captured with no focused element (`NativeTargetLease` exposes `capturedWithoutFocus`), and the frontmost
   application's pid still equals `lease.processIdentifier`, and `AXTargetState.focusedIdentity()` is still nil;
4. secure input is off, the lease is valid, and `canCommit()` holds.

A focused element that exists but cannot be read keeps today's path (paste, then `uncertain`). Leases with a focused
element are never routed to the compatibility path, so ChatGPT, Cursor, T3 and native fields behave exactly as now.

**D3 — Exactly one paste, text stays on the clipboard.** The path reuses `ClipboardPasteTransaction` through a sibling
`pasteUnobserved`: snapshot, write, `beforePaste`, re-check ownership and `canCommit`, mark `.paste`, post ⌘V once,
no retry. Nothing can be observed, so the clipboard is **not** restored (same rule as an unconfirmed paste today). The
help text says the dictated text stays on the clipboard.

**D4 — Truth and presentation.**

- New `DeliveryConfirmation.unobservable`. `DeliveryReceipt.init` accepts `.accepted` for it only when `.paste` was
  committed; `isConfirmedInsertion` stays false, so no anchor, no restore, no correction-capture seed.
- `DeliveryReceipt.status` for that receipt is `.uncertain`. History therefore never says `inserted`.
- `SessionPresentation`: `.completed` with `deliveryStatus == .uncertain` shows the quiet done state with the message
  `delivery.compat_pasted` ("已按兼容模式粘贴，Utter 无法确认结果。" / "Pasted in compatibility mode; Utter cannot confirm the result."), not the
  unconfirmed notice. This is the owner's adopted recommendation for open question 3.
- Plan item C audits every consumer of `SessionCompletion.accepted` and `DeliveryReceipt.disposition == .accepted`
  (history, workflows, ingress/API status, correction capture, lexicon learning). If any consumer would treat the
  receipt as a confirmed insertion, the fallback is `disposition == .uncertain` with a quiet-presentation flag; this
  spec is then amended before the PR merges.

**D5 — Switch-off message.** When there is no focused element and the compatibility path does not apply, the result is
`notCommitted` with the new message `delivery.opaque_target`: "此应用不允许 Utter 直接写入。可以复制文本，或在设置里开启兼容模式。" /
"This app does not let Utter write into it directly. Copy the text, or turn on compatibility mode in Settings." The
"target changed" message stays for every other case.

**D6 — Setting name, place and wording (open question 4).** General → Output, directly under "允许剪贴板粘贴":
"兼容模式：向无法检查的输入框粘贴" / "Compatibility mode: paste into inputs Utter cannot inspect". Help: "用于微信等 Utter 读不到内容的输入框。
Utter 只粘贴一次，无法确认是否成功，口述文本会留在剪贴板里。需要先开启『允许剪贴板粘贴』。"

**D7 — Apps the acceptance run covers (open question 5).** WeChat, plus the first of Feishu and QQ whose probe shows no
focused element. If both expose one, the run records that they are outside this path and WeChat alone covers it; the
owner may then ask for a third app.

**D8 — Diagnostics.** One log line per compatibility delivery: `Delivery completed: …, path: compatPaste, target: opaque`.
No text, no field content, no app name beyond what existing logs already carry.

**D9 — Rollback and kill switch.** Turn the setting off (no new build) or `defaults write com.opentype.voiceinput
allowOpaqueTargetPaste -bool false`. A code rollback is a revert; nothing else depends on it.

## Interfaces changed (all additive)

- `SettingsValues.allowOpaqueTargetPaste`, `VoiceInputSettings`, `SettingsStore` load/persist, `AppSettings`, one `Toggle`
  in `GeneralSettingsOutputSection`, four localized strings (2 settings, 2 delivery) in `en` and `zh-Hans`.
- `DeliveryRequest.allowsOpaquePaste` (default `false`), filled from settings in `VoiceSessionJob+Delivery` and the
  deferred-replacement path (which passes `false`: replace is out of scope).
- `DeliveryConfirmation.unobservable`; `DeliveryReceipt` acceptance rule; `SessionPresentation` mapping.
- `NativeTargetLease.capturedWithoutFocus`; `NativeOutputBackend.deliver` chooses the path; `ClipboardPasteTransaction.pasteUnobserved`;
  `DeliveryPath.compatPaste`.

## Test plan

Automated (fakes, no hardware):

- Guards, each with a test that posts **zero** pastes: secure input on; frontmost pid differs from the lease; lease
  invalid; `canCommit` false; `allowClipboardPaste` off; setting off; command is replace, delete, undo or restore; lease
  captured with a focused element; `AXIsProcessTrusted` false; focused element appears before the write.
- Exactly one paste is posted per delivery, including when the clipboard is overwritten by another app between write and
  post (then no paste, `uncertain`), and the clipboard is not restored.
- Receipt truth: `.unobservable` is never `inserted`, never gives an anchor or selection edit, never accepted without
  `.paste`; a receipt built with `.unobservable` and no paste is `notDelivered`.
- Presentation: `.completed` + `.uncertain` shows the quiet state with the compat message; `.failed` + `.uncertain`
  still shows the unconfirmed notice (unchanged from 0.0.62).
- Settings round trip with default `false`; the toggle is disabled while clipboard paste is off.
- Log line contains no text (reuse the no-leak pattern of the diagnostic tests).
- Mutation checks: drop the focus-loss check, drop the pid check, drop the secure-input check, post twice; each makes a
  test fail.

Hardware (owner's machine, release-style build, independent verifier or the owner's recorded waiver):

| Case | Runs |
|---|---|
| H0 feasibility, first: ⌘V from a posted event lands in the WeChat chat input with no focused element. **Stop rule:** if fewer than 9 of 10 land, the feature is dropped or redesigned and the owner is told; nothing ships. | 10 |
| WeChat, switch on, then dictation | 10, each inserted exactly once |
| Second opaque app (D7) | 10 |
| WeChat, switch off | 3: `notDelivered`, nothing written, the new message |
| T3 Code, Cursor, ChatGPT, TextEdit unchanged | 1 each |
| Secure input (a password field) with the switch on | 1: nothing pasted |

## Not covered, stated

Apps that expose a focused element but reject paste; multi-window apps where focus moves between capture and write
(guarded by the pid check, not by content); input methods that intercept ⌘V.

## Request to the owner

Approve or change D1 to D9, in particular D4 (quiet presentation with `uncertain` kept in history) and the H0 stop
rule. The plan is submitted together; each stays a separate decision.
