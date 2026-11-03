# Verification: A compatibility switch for input boxes Utter cannot inspect

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

Draft on purpose: the automated half is done, **H0 and the hardware matrix are not**. Do not read this as release
evidence until those sections are filled in and the owner approves this stage.

## Deviation from the plan, stated

The plan orders H0 (does a posted ⌘V land in WeChat with no focused element) before any wiring. The implementation was
written while H0 was still waiting for the owner to use WeChat. The stop rule is unchanged: if H0 fails, this code is
not merged or released. H0 is a gate for the merge, not for writing the branch.

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
- Feishu: **does** expose a focused element (`evidence/batch0-feishu-qq-focus.txt`), so it is outside this path and is
  checked only as an unchanged app.
- QQ: not yet sampled. Per spec D7 the second opaque app is QQ if it turns out to be opaque; otherwise WeChat alone
  covers this path and the owner may ask for another app.

## H0 and hardware verification — NOT DONE

Verifier: the implementing assistant. **Waiver:** the owner waived an independent verifier and allowed the installed
Utter 0.0.62 to be replaced for the run, re-granting permissions afterwards (chat answer "批准", 2026-11-03 23:28
UTC+8). The verification stage itself still needs the owner's approval.

| Case | Runs | Result |
|---|---|---|
| H0: posted ⌘V lands in the WeChat chat input with no focused element (**stop rule: fewer than 9 of 10 means nothing ships**) | 10 | not run |
| WeChat, switch on, dictation | 10 | not run |
| Second opaque app (QQ if opaque) | 10 | not run |
| WeChat, switch off | 3 | not run |
| T3 Code, Cursor, ChatGPT, TextEdit unchanged | 1 each | not run |
| Secure input (password field) with the switch on | 1 | not run |

## Rollback

Turn the setting off, or `defaults write com.opentype.voiceinput allowOpaqueTargetPaste -bool false`, or revert the
commits. With the setting off the only difference from 0.0.62 is the clearer message for apps without a focused element.
