# Verification: Electron delivery uncertain

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan](plan.md)

Intent, spec and plan were approved together on 2026-10-25 18:50 UTC+8. Batch 0 (measurement gate) ran first. After its report the user decided to continue with Batches 1–4 unchanged (chat: 直接开始 Batch 1–4, spec erratum to follow). Batches 1–4 are implemented and unit-tested; **Batch 5 (hardware verification by an independent verifier) has not started**, so nothing here shows the fix works on a real Mac yet.

## Batch 0 — measurement gate (run 2026-10-25, 18:55–19:28 UTC+8)

### Scope actually run

The user narrowed Batch 0 to Dia only: the three field types on the local test page and Dia's own address bar and find bar. **Not run:** Safari (D6), Feishu/Lark, any second Electron app. Those rows of the plan stay open.

### Method and safeguards

- Probe: [`evidence/batch0-delivery-probe.swift`](evidence/batch0-delivery-probe.swift), test page: [`evidence/delivery-test-page.html`](evidence/delivery-test-page.html) (static, no script, no network).
- **T1** = AX selected-text write of the marker `UTTERPROBE-T1`, watched for 4 s. **T2** = clipboard snapshot, marker `UTTERPROBE-T2`, Cmd+V posted with `CGEvent` at `.cghidEventTap` (the exact mechanism in `NativeDeliveryKeys.swift`), watched 4 s, clipboard restored and compared byte-for-byte (identical in every run that ran T2).
- The probe never reads or prints field content, only lengths and flags. It writes only into empty fields (or a whole-selected field with `--allow-selected-all`), requires the target app to be frontmost, and waits for HID idle.
- Frontmost app was restored to Mail after every run.

### Deviations from the plan (disclosed)

1. The probe source is committed under `evidence/` although the plan said `/tmp`; it is the instrument the results depend on.
2. The user was away (HID idle 366 s), so the planned "user focuses the field" step was replaced by AX focus (`AXFocused`) and then by one real synthetic click with the cursor restored. Both are recorded per run. A real click is closer to Utter's real use; AX focus is not.
3. Invalid runs, kept for transparency: [`batch0-invalid-run1-dia-input-focused-webarea.txt`](evidence/batch0-invalid-run1-dia-input-focused-webarea.txt) targeted an `AXWebArea`, not a text field (probe bug, fixed with a role guard). A first 27-run sweep was discarded because my idle guard skipped the click; the results below come from the corrected sweep.
4. Twice I compiled the probe before an edit had finished and measured with stale code; both were caught and rerun. The committed source matches the binary used for every result below (source saved 19:25:01, binary built 19:25:04; recompiles cleanly).

### Results

| Target | `ChromeAXNodeId` | Empty value | T1 AX write | T2 paste |
|---|---|---|---|---|
| Dia `<input>` | yes | `""` | returns success, **no effect** | effective |
| Dia `<textarea>` | yes | `""` | returns success, **no effect** | effective, but unstable in sequence (below) |
| Dia `contenteditable` (`role=textbox`) | yes | `""` | returns success, **no effect** | effective, but unstable in sequence (below) |
| Dia address bar (`AXTextArea`) | **no** | URL text | **effective** | not run (T1 works) |
| Dia find bar (`AXTextField`) | **no** | `""` | **effective** | not run (T1 works) |

Conclusions that the spec's design rests on:

1. **D1 premise holds for Chromium page content in a browser**: the `AXSelectedText` write is reported as success and nothing appears, exactly like the Cursor and T3 Code measurements. Today's code would mark an effect, time out and return `uncertain`. This explains "输入不上去" in browser fields.
2. **Browser UI fields are not misclassified**: the address and find bar carry no `ChromeAXNodeId`, and the AX write works there. A classification by `ChromeAXNodeId` therefore leaves them on the existing native AX path. The spec's false-positive row that assumes Chromium browser UI carries the id is **wrong for Dia** and needs a corrective revision (see "Spec follow-ups").
3. **D3 is unnecessary for Dia**: empty fields report `""`, never `"\n"`. The `"\n"`-only rule stays harmless but nothing observed needs it; Batch 1 tests still cover both.
4. Paste methods are equivalent on a fresh page: 27/27 effective for Cmd+V, menu Paste and synthetic typing, 3 reps × 3 field types × 3 methods, page reloaded before each run ([`batch0-sweep.txt`](evidence/batch0-sweep.txt)).

### Anomaly: consecutive pastes in one page session

Without reloading the page between runs, T2 succeeds on some fields and silently fails on others, with the same mechanism that works after a reload. T1 had no effect in these runs, so it cannot be the cause; a distinct marker per run gave the same result as one repeated marker, so it is not de-duplication.

| Run | Order | Result (✓ pasted, ✗ nothing appeared) |
|---|---|---|
| [`sweep2`](evidence/batch0-sweep2.txt), 3 rounds | input, textarea, ce | input ✓✓✓, textarea ✗✗✗, ce ✗✓✗ |
| [`sweep3`](evidence/batch0-sweep3.txt), 3 rounds, distinct markers | input, textarea, ce | input ✓✓✓, textarea ✗✗✗, ce ✗✓✗ |
| [`sweep4`](evidence/batch0-sweep4.txt), 2 rounds, reversed | ce, textarea, input | ce ✓✓, textarea ✗✓, input ✓✓ |

It is not "only the first paste works" (input succeeds at position 3) and not purely a field type (textarea succeeded once). Cause is **unknown**. These runs used synthetic clicks while the user was away; whether real Utter dictations behave the same is not established and must be measured in Batch 5 with the real app. If it reproduces there, the product symptom stays "nothing appears" for some dictations in Chromium textareas, and the paste route alone does not fix acceptance criterion "10 consecutive dictations".

### Gate evaluation against the plan

| Plan gate question | Answer |
|---|---|
| Does T1-ineffective/T2-effective hold for Chromium browser fields? | Yes on a fresh page; unstable in sequence for `textarea` and `contenteditable` |
| Do browser UI fields need to stay on the AX path? | Yes, and the `ChromeAXNodeId` classification already does that in Dia |
| Does D3's `"\n"` rule matter? | Not in Dia |
| Does Safari need its own rule (D6)? | Not measured |

Gate decision: **continue with Batches 1–4 unchanged**, chosen by the user after this report (the offered alternatives were: submit the spec erratum first, measure Safari/Feishu/real Utter first, or stop). The spec erratum below is still owed.

### Spec follow-ups required (spec is approved; edits need a new approval)

- Correct the false-positive row: Dia's address/find bar do **not** carry `ChromeAXNodeId`; the existing risk of misclassifying browser UI is unobserved, not confirmed.
- Optionally drop D3's motivation for Chromium (`""`, not `"\n"`), or keep it as a defensive rule.
- If the sequential-paste failure reproduces with real Utter, add a design decision for it before more code is written.

### State left behind

- The test page tab is still open in the user's Dia (reload clears the markers).
- T1 wrote the marker into Dia's address bar and find bar. I sent Escape afterwards but did not verify what either shows now; neither was submitted, so nothing navigated.
- Clipboard: restored and verified identical after every T2 run.
- Nothing in Utter's Sources was changed.

### Evidence index

All logs are under [`evidence/`](evidence/) as `batch0-*.txt`: per-field runs (`dia-*`, `dia-click-*`, `dia-f-*`), `readonly-check`, the sweeps, `dia-addressbar`, `dia-findbar`, and the invalid run.

## Implementation log (Batches 1–4)

Each batch ran `swift build`, `swift test --filter UtterMacServicesTests` and `bash scripts/ci-basic-checks.sh` before its commit.

| Batch | Commit | What | Tests |
|---|---|---|---|
| 1 | `672988e` | Pure `DeliveryExpectation.expectedDocument` | 8 new, module 62 passing |
| 2 | `69cb79a` | `WebContentEditorSignature` (`ChromeAXNodeId`), `isWebContentEditor` on the target, transaction skips the AX write for web editors | module 71 passing |
| 3 | `1a81fad` | `DeliveryCompletion.path`/`target`, `logSummary`, hidden kill switch `deliveryWebEditorPasteDisabled` | module 75 passing |
| 4 | this commit | README troubleshooting entry (EN and ZH), this log | docs only |

Full `swift test` after Batch 3: 15 test bundles, 1215 tests, 18 skipped, 0 failures. The output contains CoreData `NSXPCStore` log noise from tests unrelated to this change; no test failed. `scripts/sdlc-checks.sh` and `scripts/ci-basic-checks.sh` pass.

Mutation check: with the `!target.isWebContentEditor` guard removed from `TextDeliveryTransaction`, the three new web-editor transaction tests fail (AX write reached, paste not used); restored afterwards.

### Differences from the approved plan and spec (disclosed)

1. **Guard in two places.** The plan said `supportsSelectionWrite` returns false for web editors. It does, and `TextDeliveryTransaction` also checks `isWebContentEditor` itself so a target cannot reach the ineffective write by mistake and the tests can prove it with a fake.
2. **D3 narrowed.** The placeholder rule applies only when the caret is at `0,0` and the replacement is non-empty. Batch 0 measured neither another caret position nor a delete in an empty field; those cases use the normal computation and can only end `uncertain`. In Dia the empty value is `""`, so D3 changes nothing there.
3. **"Editable" is part of the classification.** `isWebContentEditor` requires the Chromium node and a settable `AXSelectedText`. A read-only Chromium node keeps going through the paste path as before and logs `target=native`.
4. **A fourth path label.** Deleting through a key press (undo/delete flows) logs `path=keyPress`, because calling it `paste` would mislead; the spec named three values.
5. **No separate release-note file.** Release notes come from `git log --no-merges` subjects (`docs/sdlc/release-runbook.md`), so the Batch 2 and 3 commit subjects are the release-note lines. There was no troubleshooting document, so the entry lives in `README.md` and `README_zh.md`.
6. **Kill switch read per delivery** from `UserDefaults.standard`; `defaults write` taking effect on the next dictation is claimed in the README and must be confirmed in Batch 5.

### Not covered by any test yet

- Anchor flows on web editors (`replaceAnchor`, `undoAnchor`): they select a range through AX and then paste or press delete. Whether Chromium honors the AX selection write was not measured. Expected worst case is `uncertain`; check in Batch 5.
- Everything that needs a real Chromium field: classification by `ChromeAXNodeId`, the paste landing, the placeholder rule, clipboard restoration. Unit tests use fakes.
- The consecutive-paste anomaly from Batch 0.

## Batch 5 — independent verification

Not started. Requires the release-style build (`bash scripts/build-app.sh`) and a verifier who is not the implementer.
