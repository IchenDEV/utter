# Spec: The "insertion unconfirmed" notice must be compact and leave on its own

**Status:** approved
**Approved-by:** User, answered the approval question in this conversation: design A (compact, self-dismissing notice, 8 s), and approve intent, spec and plan together. PR, merge, tag and release remain separate decisions
**Approved-date:** 2026-11-03
**Upstream:** [intent.md](intent.md)

## Current behavior (read from `origin/main` at `3748367`)

| Piece | Fact |
|---|---|
| State | `SessionPresentation` maps `.failed` + `deliveryStatus == .uncertain` to `status = .uncertain`, `message = snapshot.error ?? L("delivery.uncertain")`; `keepsVisible` is true for `uncertain` and `failed`. |
| Message | Delivery paths set `reason = L("delivery.unconfirmed")` ("无法确认是否已写入。可以复制文本，Utter 不会自动再次写入。"); paths without a reason fall back to the short `delivery.uncertain`. |
| Layout | `OverlayLayout` gives `.error, .uncertain` a fixed 360 × 96 card with 18 pt corners; `OverlayContentView.hud` stacks `statusRow` and `recoveryControls` (`.bordered`, `.small` system buttons). |
| Dwell | `NativeDesktopHost.project` hides after 1.5 s only when `!keepsVisible`; `uncertain` and `failed` stay until Close. `togglePopover` re-shows the overlay when `phase == .uncertain`. |
| Clipboard | After an unconfirmed paste the clipboard keeps the dictated text (`ClipboardPasteTransaction.paste` restores only after confirmation). The AX-write path does not touch the clipboard. History records the text for every status. |

## Decisions

### D1. Presentation only

No change to `TextDeliveryTransaction`, `ClipboardPasteTransaction`, `NativeDeliveryTarget`, receipts, history, or
`SessionPresentation.status/message/keepsVisible/canCopy`. The delivery stays `uncertain`; the menu bar phase and
icon are unchanged. This keeps the change in the medium lane; anything that would make unverifiable targets
"confirm" or stay silent is a delivery change and is a separate, high-risk intent (see the intent's non-goals).

### D2. A compact, self-dismissing notice, not removal (needs the owner's explicit choice)

| Option | Effect | Why / why not |
|---|---|---|
| **A. Compact + leaves after 8 s (proposed)** | One-row notice carrying the same three facts; hides itself; reopens from the menu bar icon; text remains on the clipboard (paste path) or in History. | Removes the "must click Close" annoyance and most of the visual weight, and keeps the cue for the cases where text really did not land. |
| B. No HUD for `uncertain` | Menu bar icon and history only. | Loses the only prompt in the cases where nothing was inserted (the pre-0.0.58 Cursor failures were exactly that). Not proposed without an explicit decision. |
| C. Keep the persistent notice, restyle only | Layout fixed, annoyance kept. | Does not address "it often appears and is not needed". |

### D3. Dwell policy

- `SessionPresentation.autoDismisses: Bool` is true only for `status == .uncertain`. It is the contract-level policy
  and is independent of `keepsVisible`, which keeps meaning "show interactive controls" for layout and tests.
- `NativeDesktopHost.uncertainDwell: Duration = .seconds(8)` is the one constant (a stored property so tests can
  shorten it).
- `NativeDesktopHost.project`: after a non-busy snapshot, if `presentation.autoDismisses` schedule
  `hideOverlay` after `uncertainDwell`; else if `!keepsVisible` the existing 1.5 s path runs unchanged; `failed`
  (errors needing action, including recovery buttons) still never auto-hides.
- One private `scheduleHide(after:for:)` is used by both paths. It cancels the previous `hideTask`, and when it fires it
  hides only if the host is open and current, `state.snapshot.id` still equals the id it was scheduled for, and
  `!state.offersRestore`. A newer session therefore cannot be hidden by an older timer, which is the existing rule.
- `togglePopover`: when `phase == .uncertain`, show the overlay and re-arm `scheduleHide(after: uncertainDwell, ...)`, so
  reopening from the menu bar behaves the same as the first showing.
- Pointer hover does not pause the timer (no new host-to-view plumbing). Reopening from the menu bar is the recovery.

### D4. Layout of `.error` and `.uncertain`

New `OverlayLayout.Content.alert`. `OverlayLayout.init(appState:)` returns it for `.error, .uncertain` with a computed
size; other phases keep today's values.

```
┌────────────────────────────────────────────────────────┐
│ ⚠  无法确认是否已写入。可以复制文本，         [复制]  (✕) │
│    Utter 不会自动再次写入。                              │
└────────────────────────────────────────────────────────┘
```

- One `HStack`, vertically centered: status icon (16 pt, existing orange triangle / red mark), message
  (`.caption.weight(.medium)`, `lineLimit(3)`, wraps), then trailing controls: optional Copy capsule, optional
  recovery capsule (Open Models / Open Privacy Settings), and the existing 26 pt circular Close button
  (`ReviewButton` quiet role, with its accessibility label and tooltip).
- Capsule buttons: text, `.caption.weight(.medium)`, white 0.88 on white 0.10 fill (0.16 hover, 0.22 pressed), 0.5 pt
  white 0.08 border, 26 pt tall. They replace the system `.bordered` slabs.
- Width stays 360 (what it is today). Padding 12 horizontal, 10 vertical, 8 between items.
- Height is computed, not fixed: `max(26, messageHeight) + 20`, where `messageHeight` is the AppKit-measured height of
  the message at the width left after the icon and trailing controls, capped at three lines. Capsule widths come from
  the same measurement and are applied as explicit frames, so the text gets exactly the width the measurement assumed.
  The measurement uses a width 4 pt narrower than the real one, so a rounding difference can only add padding, never
  clip. This is the same technique as `SelectionReviewMetrics.textHeight`.
- Corner radius stays 18, surface and stroke stay `OverlayPanelSurface` (Reduce Transparency and Increase Contrast are
  honored as before). No new animation; the existing layout animation still honors Reduce Motion.
- Expected sizes: one or two lines of message → 46 pt; three lines → about 59 pt; down from a fixed 96 pt.

### D5. Strings

No new keys. The message is still `delivery.unconfirmed` / `delivery.uncertain` / the error text; the buttons use
`common.copy`, `common.close`, `hud.open_models`, `hud.open_permissions`. No localization churn and no history or
integration payload changes.

### D6. Tests

| Criterion | Check |
|---|---|
| Sizes and content kind | `OverlayLayoutTests`: for zh and en, `uncertain` with the production message, `uncertain` with the short message, and a long model error return `.alert`, width 360, a height between 46 and 60 and below 96; a three-line cap holds for a very long message. |
| Dwell policy | `SessionPresentationTests`: `autoDismisses` is true only for `uncertain`; `keepsVisible`/`canCopy` expectations unchanged. |
| Host behavior | New test with a fake `OverlayPresentationService` and `uncertainDwell` shortened: `uncertain` hides after the dwell; a newer session before the dwell is not hidden by the old timer; `failed` is not auto-hidden; `done` still hides at its existing delay path; reopening via the menu-bar entry point re-arms the dwell. |
| Real rendering | `PresentationRenderingTests` renders the `uncertain` case with the production message, plus English, plus the three error cases, in light and dark windows; the PNGs for this change go to `evidence/after-*.png`. Reviewed for clipping and alignment. |
| Real panel | A test that shows a real `OverlayPanel` for `uncertain` and asserts the window frame equals the layout size and stays inside the visible frame. |
| Nothing else moved | The full existing suite passes unchanged: `SessionPresentationTests`, `PresentationProjectionTests`, history and delivery tests. |
| Repo checks | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`; release-style build in PR CI. |

## Failure analysis

| Failure | Behavior |
|---|---|
| The notice leaves before the user reacts and the text did not land | Paste path: the dictated text is still on the clipboard. Any path: the History tab has the record with its Copy action; the menu bar icon keeps the `uncertain` state and clicking it shows the notice again. Stated as residual risk, not eliminated. |
| Timer from an older session hides a newer notice | Prevented by the id check; covered by a test. |
| Height prediction differs from SwiftUI wrapping and clips text | Fixed action widths, 4 pt measurement slack, three-line cap, and render evidence in zh and en for the longest real messages. A stop condition below applies. |
| Very long error text | Capped at three lines with truncation, as before. |
| VoiceOver or switch-control users cannot read or reach the notice within 8 s | A real limitation of any timed notice. The state is also in the menu bar icon, the History row, and reopenable. Recorded as residual risk; not mitigated by a setting in this change. |
| Reduce Transparency / Increase Contrast | Same `OverlayPanelSurface` as before. Render evidence covers dark and light; the system accessibility variants are by construction, not re-rendered. |
| Narrow display | Width stays 360, as today; `OverlayPanelPlacement` is unchanged. Displays narrower than 360 pt visible width are not a supported configuration today either. |
| Privacy | No text in logs; no new logging. |

## Rollout and rollback

1. Ship in a normal release (next patch, v0.0.62 if the owner authorizes the tag).
2. Stop conditions: clipped text in any evidence render, any change in `uncertain` recording, a timer hiding a newer
   session, or a regression in the other HUD states.
3. Rollback: revert the commit. The previous behavior is the persistent notice; no data or settings migrate.

## Approval record

The owner chose D2 option A and the 8 s dwell, and approved the spec as written (2026-11-03, chat answer).
