# Verification: Electron delivery uncertain

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan](plan.md)

Intent, spec and plan were approved together on 2026-10-25 18:50 UTC+8. Only Batch 0 (measurement gate) has run. Batches 1–5 have not started; the gate decision below belongs to the user.

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

Gate decision: **pending the user** (continue unchanged, revise D1/D3, or open a Safari rule; also whether to measure the unmeasured rows first).

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

## Batches 1–5

Not started.
