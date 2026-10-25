# Plan: Dictated text must land in web content editors (Electron apps and Chromium browsers)

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Previously approved:** none (the earlier draft of this plan was never approved; it was replaced because the intent and spec scope were widened on 2026-10-25).
**Upstream:** [spec](spec.md) (revision 2026-10-25, pending approval)

Each code batch is one commit. Before every commit run `swift build`, the batch's focused `swift test --filter UtterMacServicesTests`, and `bash scripts/ci-basic-checks.sh`. Every file stays under 300 lines. The implementer is one agent; the independent verifier in batch 5 is a different one. All changes are in `UtterMacServices`; `DeliveryCompletion` is internal to that module, so no contract in `UtterContracts` changes.

## Work items

### Batch 0: measurement gate (no shipped code)

The spec's classification is measured only in Cursor and read-only in T3 Code and Dia. This batch measures what the revised scope depends on before any code is written. Probe code lives outside the repo (`/tmp`), and only the page and the results are committed.

- [ ] Commit a static test page `evidence/delivery-test-page.html` with a single-line `<input>`, a `<textarea>`, and a `<div contenteditable>`, all empty. No network, no scripts that read or send anything.
- [ ] Extend the read-only probe to run, per field, the same protocol as spec T1 and T2: record role, attribute names, empty `AXValue` (`""` or `"\n"`), then T1 (AX selected-text write of a short marker, watch `AXValue` for 4 s) and T2 (clipboard snapshot, paste, watch `AXValue`, restore the clipboard). Markers only, on empty fields of our own page; nothing from the user's real fields is read or written.
- [ ] Run it in **Dia** for the three field types, then for the address bar and the find bar (browser UI), then in **Feishu** (an input the user chooses) and in **Safari** for the three field types. The user clicks into each field when the probe announces it (about 10 minutes, user present).
- [ ] Record results in `verification.md` under "Batch 0". Gate decision for the human:
  - If Chromium browser fields behave like Cursor (T1 ineffective, T2 works): continue with batches 1 to 4 unchanged.
  - If any Chromium field type behaves differently (for example T1 works, or the empty value is not `"\n"`): stop; the spec's D1 or D3 is revised and returns to the user.
  - Safari: report the result only. If WebKit shows the same ineffective write, propose a narrower signature as a spec revision (D6); nothing for Safari is implemented in this plan.

### Batch 1: pure expectation (spec D3)

- [ ] `Sources/UtterMacServices/DeliveryExpectation.swift` (pure): `expectedDocument(document:range:replacement:isWebContentEditor:)`. For a web content editor whose document is exactly `"\n"`, the expected document is the replacement with no trailing newline; every other case delegates to the existing `DeliveryTextChange`.
- [ ] Tests in `Tests/UtterMacServicesTests/DeliveryExpectationTests.swift`: `"\n"` with selection 0,0 on a web editor; the same document on a native target (unchanged); non-placeholder documents; empty document `""` (a plain `<input>` or `<textarea>` if Batch 0 measures that); surrogate-pair boundaries; invalid ranges return nil as today.

### Batch 2: classification and path selection (spec D1, D4)

- [ ] `DeliveryTextTarget` gains `isWebContentEditor: Bool`. `NativeDeliveryTarget` implements it as "the focused element exposes `ChromeAXNodeId`" through `AXUIElementCopyAttributeNames`; any error means false. `supportsSelectionWrite` returns false when it is true. `expectedDocument` delegates to `DeliveryExpectation`.
- [ ] `TextDeliveryTransaction.deliver`: for a web content editor with `allowsClipboardPaste == false`, return `notCommitted` with `delivery.unavailable` before any write or key post. The paste path is otherwise unchanged.
- [ ] Update the test fake `TransactionTarget` in `TextDeliveryTransactionTests.swift`; add tests with a counting fake: a web target never calls `writeSelection` and pastes exactly once; an unconfirmed paste is not retried; with clipboard disabled it returns `notCommitted` and touches neither AX nor the clipboard; native targets keep the AX-first path.

### Batch 3: logging and kill switch

- [ ] `DeliveryCompletion` gains `path` (`accessibility`, `paste`, `clipboardOnly`) and `target` (`web`, `native`), set by the transaction. `NativeOutputBackend` logs them in `Delivery completed`; no text is logged.
- [ ] Kill switch: `NativeOutputBackend` reads the hidden default `deliveryWebEditorPasteDisabled`; when true it treats every target as native (previous behavior).
- [ ] Tests: the log line carries path, target, and disposition and never the text; the kill switch restores the AX-first path.

### Batch 4: docs

- [ ] Troubleshooting entry: what "can't confirm the write" means, the HUD copy button, and the kill switch `defaults write com.opentype.voiceinput deliveryWebEditorPasteDisabled -bool true`. State plainly that targets without `ChromeAXNodeId` (Safari, Firefox) are not covered.
- [ ] Release note line.

### Batch 5: verification (independent verifier)

- [ ] 10 consecutive dictations into the Cursor agent input: text exactly once each time, `Delivery completed` shows `path=paste target=web` and `accepted`, clipboard restored afterwards.
- [ ] The same in T3 Code (Nightly); if its field lacks `ChromeAXNodeId` or behaves differently, record it and return to the spec.
- [ ] The same in Dia on the test page: 10 dictations each into the `<input>`, the `<textarea>`, and the `contenteditable` field.
- [ ] The same in one more Electron app (Feishu or one the user names); differences are recorded and returned to the spec.
- [ ] Chromium browser UI: the address bar and the find bar receive dictated text exactly once; the clipboard is restored after an `accepted` paste.
- [ ] Native targets: TextEdit and Notes still `accepted` through the AX path, with no extra clipboard writes beyond today's.
- [ ] Cases that must not double insert: multi-line payload, non-empty field with the caret mid-text, clipboard delivery disabled, secure input.
- [ ] Kill switch on: Cursor and Dia revert to the previous `uncertain` behavior; kill switch off again: fixed.
- [ ] Safari: confirm that its behavior is unchanged from before (it is not classified) and record Batch 0's measurement.
- [ ] Record everything in `verification.md`, including the independent verifier's identity and result.

## Verification plan

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] Release-style build (`bash scripts/build-app.sh`) and a run of that build for batch 5, because Accessibility and paste behavior depend on the signed app.
- [ ] Hardware checks from batch 5, repeated by the independent verifier.

## Human gates

- Each stage artifact (`intent`, `spec`, `plan`, then `verification`) needs explicit approval before the next stage starts. All three upstream artifacts are currently `pending approval` after the scope revision.
- The Batch 0 gate decision (above) is the user's: continue unchanged, revise D1/D3, or open a Safari rule.
- PR approval, then release approval, for this high-risk change; the release is not cut without the independent verifier's recorded result.
- A need to change the classification beyond `ChromeAXNodeId` (for example WebKit targets) or to add any app-name rule returns to the user as a spec revision.
