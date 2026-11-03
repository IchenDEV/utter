# Verification: A compatibility switch for input boxes Utter cannot inspect

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

The automated half is done. **H0 and the hardware matrix were not run**: the owner chose not to test and delegated the
judgement (see "H0 and hardware verification"). This file therefore proves the guards and the receipt contract, not that a
posted ⌘V lands in WeChat. That is a stated, owner-accepted residual risk.

## Deviation from the plan, stated

The plan orders H0 (does a posted ⌘V land in WeChat with no focused element) before any wiring. The implementation was
written while H0 was still waiting for the owner to use WeChat, and H0 was never run (see below). The stop rule was
written for a failed H0 ("fewer than 9 of 10 means nothing ships"); it was not evaluated, because no round fired.

## Implemented (plan items A to E)

| Item | Result |
|---|---|
| A. Setting | `allowOpaqueTargetPaste`, default `false`, persisted; `VoiceInputSettings.allowOpaqueTargetPaste` is false while clipboard paste is off; toggle under "允许剪贴板粘贴" is disabled while that is off; strings in `en` and `zh-Hans`. |
| B. Receipt and presentation | `DeliveryConfirmation.unobservable`; accepted only with a committed `.paste`; status `.uncertain`; never inserted, no anchor, no selection edit. `.completed` + `.uncertain` shows the quiet state with `delivery.compat_pasted`; `.failed` + `.uncertain` is unchanged. |
| C. Consumer audit | Below. |
| D. Path | `NativeTargetLease.capturedWithoutFocus`; `OpaquePasteDelivery` (route and deliver); `ClipboardPasteTransaction.pasteUnobserved`; `DeliveryPath.compatPaste`, `DeliveryTargetKind.opaque`; `NativeOutputBackend` routes before the existing path; `delivery.opaque_target` when the switch is off. |
| E. Mutation checks | Below. |

### Consumer audit (item C)

Every user of `SessionCompletion.accepted` or `DeliveryReceipt.disposition == .accepted`:

| Consumer | Behavior with an unobservable receipt | Verdict |
|---|---|---|
| `SessionDriver.finish` | phase `.completed`, `deliveryStatus` `.uncertain`; history record stored as `uncertain` | intended (quiet presentation, truthful history) |
| `SessionOutputState.remember` | stores recent text with **no anchor** | safe: spoken edits need an anchor (`recentAnchor()` throws), none is available |
| `VoiceWorkflowFactory.settle` | remembers output; correction capture needs `receipt.anchor`, which is nil | safe: nothing is learned from an unverified paste |
| `VoiceSessionJob+InstantInsert` | would install background reformatting that needs an anchor | **changed**: no follow-up when the status is `.uncertain`; the raw text stays as pasted |
| `DeferredFormatWork.install` | only reached through the follow-up above | safe after the change |
| `VoiceSessionJob+Editing` | record created as for any accepted delivery | intended |
| `OpenTypeService+Execution.settleExecution` | API sessions complete; API sessions have no target lease, so never reach this path | not reachable |
| `HistoryStore` filter (`nil` or `inserted` only) | unverified records are excluded from learning | intended |
| `SessionDriver+Settlement.terminal` | performance terminal `.uncertain` | intended |

Verdict: no consumer treats the receipt as a confirmed insertion; one needed a guard and has it.

### Automated evidence

- `swift test`: 631 tests, 26 skipped, 0 failures. `bash scripts/ci-basic-checks.sh` and `bash scripts/sdlc-checks.sh`: passed.
- CI on this branch failed once in `DesktopOverlayDwellTests.testUnconfirmedNoticeLeavesAfterTheDwell` (a test from
  the earlier compact-notice change, not touched by this feature): it slept 40 ms and asserted the 120 ms dwell
  had not ended, and a stalled runner made that sleep outlast the dwell. The test now measures the elapsed time
  until the notice leaves and requires it to be at least the dwell, so a stall can only make it pass. It passed three
  local runs, and shortening the dwell to a quarter makes it fail (mutation kill); the mutation is restored.
- New tests: `OpaquePasteDeliveryTests` (routing, every guard posts zero pastes, exactly one paste, clipboard not restored,
  clipboard overwritten before the paste, failed post, no key events, log line without text, backend with the switch on
  and off), `UnobservablePasteReceiptTests`, a presentation test, settings round-trip and snapshot tests.
- Mutation checks, each run against `OpaquePasteDeliveryTests` and restored afterwards (the restored suite passes):

| Mutation | Result |
|---|---|
| Drop the "no focused element now" check | failed (2 tests) |
| Drop the frontmost-pid check | failed (2 tests) |
| Drop the secure-input check | failed (1 test) |
| Post the paste twice | failed (3 tests) |
| Drop `capturedWithoutFocus` | failed (2 tests) |
| Drop the Accessibility-trusted check | failed (2 tests) |
| Drop the lease-validity check | failed (1 test) |

## Not covered by unit tests

- The real `AXTargetState.focusedIdentity()`, `AXIsProcessTrusted()`, frontmost-app and CGEvent posting behind
  `OpaqueDeliveryEnvironment.native`: covered only by the hardware matrix.
- Apps that expose a focused element but reject paste; focus moving between capture and write inside the same app.
- The switch-off message for non-insert commands in an opaque app keeps the old "target changed" text.

## Measurements so far

- WeChat: no focused element in 7 of 7 samples (`evidence/batch0-wechat-focus.txt`).
- Feishu: exposes a focused element in every sample, so it is outside this path and is checked only as an unchanged app.
- QQ: one "no focused element" sample, then a focused text area 130 ms later in the same visit, so it is not an opaque
  target either (`evidence/batch0-feishu-qq-focus.txt`). Per spec D7, with neither opaque, WeChat alone covers this
  path; the owner may still ask for another app.

## H0 and hardware verification — NOT RUN, owner waived

Verifier: the implementing assistant. **Waivers:** the owner waived an independent verifier and allowed the installed
Utter 0.0.62 to be replaced for the run (chat answer "批准", 2026-11-03 23:28 UTC+8). After two probe windows with no
WeChat use, the owner answered "你凭根据感觉来搞吧，不要我实测了" (2026-11-04 02:44 UTC+8): no owner testing, and the
judgement is delegated. The verification stage itself still needs the owner's approval.

What happened to H0: the probe (`/tmp/axprobe/h0paste`, outside the repository) waits for WeChat in front, idle for
5 s and no focused element, then posts ⌘V once per round with a marker, never Return. Window 1 (00:36–01:06) and
window 2 (01:07–02:07) both ended with `rounds=0`; WeChat was never in front and idle. It posted nothing, so the
9-of-10 stop rule has no result to apply to.

| Case | Runs | Result |
|---|---|---|
| H0: posted ⌘V lands in the WeChat chat input with no focused element (**stop rule: fewer than 9 of 10 means nothing ships**) | 10 | not run (0 rounds fired) |
| WeChat, switch on, dictation | 10 | not run |
| Second opaque app: none found (Feishu and QQ both expose a focused element); recorded, not run | — | n/a |
| WeChat, switch off | 3 | not run (the installed 0.0.62 ended 8 of 8 WeChat dictations in history as `notDelivered`, which is the switch-off behavior) |
| T3 Code, Cursor, ChatGPT, TextEdit unchanged | 1 each | not run; the normal path is untouched when a focused element exists (covered by `NativeOutputBackend` tests with the switch on and off) |
| Secure input (password field) with the switch on | 1 | not run; the guard is covered by a unit test and a mutation check |

### Judgement in place of the run (assistant's, not evidence)

- The key posting is `NativeDeliveryKeys.prepare`, the same function the normal, field-used paste path calls; only
  the target app's acceptance of ⌘V is unmeasured.
- WeChat's input box is invisible to Accessibility, but that says nothing about whether it accepts ⌘V when it holds
  keyboard focus; many dictation tools paste into it. Unmeasured here.
- If ⌘V does not land, the failure is bounded: the switch is off by default, the dictated text stays on the clipboard,
  and the message says Utter cannot confirm the result. Today the same dictation ends as `notDelivered` with nothing
  written.
- Combined branch (`#144` + this change, no conflicts): every test bundle except `OpenTypeTests` passes locally; an
  ad-hoc `0.0.63` app builds with the new strings bundled. Both PRs' CI passed on their own heads.
- After release, the first WeChat dictation with the switch on settles this: a history record `uncertain` plus the
  `delivery.compat_pasted` message, and whether the text appears. A report that it does not appear means turn the
  switch off or revert (Rollback).

## Rollback

Turn the setting off, or `defaults write com.opentype.voiceinput allowOpaqueTargetPaste -bool false`, or revert the
commits. With the setting off the only difference from 0.0.62 is the clearer message for apps without a focused element.
