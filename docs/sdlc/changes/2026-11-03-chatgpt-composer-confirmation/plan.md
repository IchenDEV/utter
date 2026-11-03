# Plan: Confirm a paste into an empty-looking web editor whose placeholder disappears

**Status:** approved
**Approved-by:** User, chat answer "批准" (22:35 UTC+8) to the compound question "是否批准 spec 和 plan，以及是否含 D5". The reply did not say 含/不含; the spec's stated default (include D5) is applied and is open to reversal at review. PR, merge, tag and release remain separate decisions
**Approved-date:** 2026-11-03
**Upstream:** [spec.md](spec.md)

## Work items

| # | Item | Files | Check |
|---|---|---|---|
| A | `DeliveryExpectation` returns the set of values that prove the text landed (D1, D2); the lone-`"\n"` rule is kept | `Sources/UtterMacServices/DeliveryExpectation.swift`, `Tests/UtterMacServicesTests/DeliveryExpectationTests.swift` | Unit tests for the measured shapes and every negative case in the spec's test plan; existing tests unchanged except for the changed return type. |
| B | `DeliveryTextObservation.confirm` accepts the set (D4) | `Sources/UtterMacServices/DeliveryTextObservation.swift`, its tests with a fake clock | Becomes-the-text confirms, stays-original and becomes-other time out; deadline and cancellation unchanged. |
| C | `NativeDeliveryTarget.confirm` and `insertionAnchor` use the set, and an unchanged field is still never accepted (D3) | `Sources/UtterMacServices/Native/NativeDeliveryTarget.swift`, route tests with the fake target | Anchor accepted for either value and rejected for others; no new write paths. |
| D | Counts-only diagnostic on timeout (D5), **included** (default applied after the owner's bare "批准") | `Sources/UtterMacServices/DeliveryTextObservation.swift` (or a new small file), `DeliveryRoute.swift`, tests | The line has numbers and flags only; a test asserts that none of the observed or expected text appears in it. |
| E | Mutation checks: remove the extra candidate, drop `replacement != document`, drop the `(0, 0)` guard | local only, restored after | The matching tests fail each time; recorded in `verification.md`. |
| F | Repo checks, release-style build, independent hardware verification, `verification.md` | `verification.md`, `evidence/` | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`; the hardware matrix of the spec by a verifier who is not the implementer. |
| G | PR, CI, then (only with the owner's authorization) merge, tag `v0.0.63`, release | GitHub | `SDLC Gate` green; release per `release-runbook.md`; the `production` approval is the owner's. |

Order: A, B, C, (D), E, F, G. Run the focused tests after each item. Commit subjects become the in-app release notes, so
they are written for users, for example "fix: confirm dictation into an empty ChatGPT composer instead of showing the unconfirmed notice".

## Verification plan

- **Automated:** the unit tests above, then the full suite and both scripts.
- **Hardware:** the matrix in the spec, with `evidence/batch0-ax-shape-watcher.swift` recording shapes and the unified log
  and history rows recording results. The independent verifier is named in `verification.md`; if the owner waives
  independence, the waiver is recorded there.
- **Runtime:** the installed Utter 0.0.62 is the owner's daily driver and shares its bundle id. The hardware run uses the
  release-style build of this branch only after the owner agrees to replace or stop the installed app for the run.
- **Not covered, recorded:** multi-paragraph text in ChatGPT, ChatGPT in a browser tab, the second cause of `uncertain`
  (unless a follow-up intent covers it).

## Rollback

Revert the change commits. The previous behavior is the unconfirmed notice on empty ChatGPT composers; no settings,
data or permission change is involved. Turning the web path off with the existing hidden switch
`deliveryWebEditorPasteDisabled` also disables the new rule.
