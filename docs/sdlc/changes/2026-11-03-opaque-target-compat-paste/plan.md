# Plan: A compatibility switch for input boxes Utter cannot inspect

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [spec.md](spec.md)

Nothing here starts until the spec is approved. Each item ends with its focused tests green before the next starts.

## Work items

| # | Item | Files | Check |
|---|---|---|---|
| H0 | Feasibility on hardware, **before any wiring**: with the owner present, a posted ⌘V reaches the WeChat chat input when there is no focused element. A throwaway probe outside the repository, no text logged, one paste per run. | none in the repository; result in `evidence/` | 9 of 10 land, else **stop** and report to the owner. |
| A | Setting `allowOpaqueTargetPaste` (default false) end to end, plus the disabled-while-clipboard-paste-off toggle and the strings | `SettingsValues`, `VoiceInputSettings`, `SettingsStore+Load/+Persistence`, `GeneralSettingsOutputSection`, `en`/`zh-Hans` `Localizable.strings` | Settings round-trip tests; localization completeness check already in `ci-basic-checks.sh`. |
| B | `DeliveryConfirmation.unobservable`, the receipt acceptance rule, `DeliveryRequest.allowsOpaquePaste`, `SessionPresentation` mapping | `DeliveryServices.swift`, `SessionPresentation.swift`, `VoiceSessionJob+Delivery.swift` | Receipt-truth and presentation tests from the spec. |
| C | Audit every consumer of `accepted` and `disposition == .accepted`; record the list and the verdict per consumer in `verification.md`. Fall back to the `uncertain` + quiet-flag design only if a consumer would misread the receipt (the spec is amended first). | read-only audit, tests where a consumer needs one | Written list; no consumer treats the receipt as a confirmed insertion. |
| D | `NativeTargetLease.capturedWithoutFocus`, `ClipboardPasteTransaction.pasteUnobserved`, `DeliveryPath.compatPaste`, the routing in `NativeOutputBackend.deliver`, and the switch-off message | `NativeTargetLease.swift`, `ClipboardPasteTransaction.swift`, `DeliveryRoute.swift`, `NativeOutputBackend.swift` | Every guard test posts zero pastes; one paste per delivery; the clipboard is not restored; no text in the log line. |
| E | Mutation checks: drop the focus-loss check, the pid check, the secure-input check; post twice | local only, restored after | The matching tests fail each time; recorded in `verification.md`. |
| F | Repo checks, release-style build, hardware matrix of the spec by a verifier who is not the implementer (or the owner's recorded waiver) | `verification.md`, `evidence/` | `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`; the matrix. |
| G | PR, CI, then (only with the owner's authorization) merge, tag, release | GitHub | `SDLC Gate` green; release per `release-runbook.md`; the `production` approval is the owner's. |

Order: H0, A, B, C, D, E, F, G. Commit subjects become the in-app release notes, so they are written for users, for
example "feat: add a compatibility mode that pastes into inputs Utter cannot inspect, such as WeChat".

## Release shape

This change and the ChatGPT composer confirmation (PR #144) are independent. They can ship in one release or two. The
owner decides; the default is one release after both are verified, because both need the same hardware session and one
reinstall.

## Verification plan

- **Automated:** the tests in the spec, the full suite, both scripts, the mutation checks.
- **Hardware:** the matrix in the spec. The installed app is the owner's daily driver and shares the bundle id; a local
  build is ad-hoc signed and does not keep Accessibility and Input Monitoring grants, so the run needs the owner's
  agreement to re-grant them, or a build signed with the release identity.
- **Not covered, recorded:** the items under "Not covered" in the spec.

## Rollback

Turn the setting off, or revert the commits. With the setting off the only difference from 0.0.62 is the clearer
message for apps without a focused element.
