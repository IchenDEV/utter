# Release: Utter v0.0.54

**Status:** blocked
**Approved-by:** —
**Approved-date:** —
**Upstream:** [Verification](verification.md)

## Candidate

- Version: `v0.0.54`.
- Protected main commit: `8d1134ce664fa4dd878389529cf1bf41721af53a`.
- Annotated tag object: `3ad41f65abb1958f937c7b406bb0aedfdee3dd36`.
- [Merged corrective PR #125](https://github.com/IchenDEV/utter/pull/125).
- [Exact-main CI](https://github.com/IchenDEV/utter/actions/runs/38860187195)
  passed repository checks, full tests, release-style packaging, and SDLC Gate.
- [Release run 38861433092](https://github.com/IchenDEV/utter/actions/runs/38861433092)
  failed its complete candidate tests. Production was skipped, with no approval.

The candidate completed 1,143 XCTest cases with 18 skipped and one failure in
`UtilityTests.testGenerationPreparationKeepsMainActorResponsive`, line 271.
Its MainActor heartbeat counter was zero. One Swift Testing case passed.
The current off-main preparation implementation uses `Task.detached`; the
timing-based test does not synchronize worker entry with its probe. This is
a scheduling-race hypothesis requiring deterministic validation, not evidence
that the application performed file copies on MainActor.

The main tree matches the verified PR tree. The owner authorized the merge and
single-maintainer review settings. Mandatory PRs, strict CI, resolved review
conversations, blocked force pushes/deletions, and no bypass actors remain.
Production's human approval configuration is unchanged.

## Human decision

After complete candidate tests and independent readiness verification pass,
request production authorization for this exact run. The v0.0.53 production
approval does not authorize this run. Record the user's decision and GitHub's
approval readback before claiming deployment is authorized.

## Required distribution evidence

- Developer ID app and DMG signatures use certificate SHA-256
  `1B499618154DEB0204896CDB199AA65D25EDA2188FEDBB0E29A73063728E4112`,
  team `G9L7H3T3D5`; the DMG has a secure timestamp.
- Apple accepts this run's notarization submission and the ticket is stapled.
- Both DMG and app Gatekeeper checks pass, with matching mounted contents.
- Published DMG and SHA-256 sidecar pass download and byte-equality checks.
- Independent download/signature/ticket verification passes on the published
  asset. No app launch or clean-machine interaction is implied by these checks.

All distribution outcomes remain unexecuted. The earlier local signed fixture and
v0.0.53 Apple acceptance do not establish them for this version.

## Public disclosure scope

The source and added public evidence passed credential and independent audits.
Public evidence uses redacted machine paths and redundant commit emails; raw
records remain private. Earlier GitHub snapshots are not claimed to be purged.
Only public certificate/team/fingerprint metadata is needed for verification.

## Rollback and immutable history

Preserve failed `v0.0.53` at tag object
`b8e869cddca904cd525ece4fcb36d55fd4a14a33` and public `v0.0.52`.
Never move a release tag or replace same-version published assets. Stop on a
signing, notarization, Gatekeeper, mounted-content, or checksum failure and
preserve its first failure. Revert source through a reviewed PR if needed.
If a published release needs withdrawal, restore the prior latest recommendation
without replacing assets and disclose the older artifact's signing status.

The bounded corrective work and its continuous owner authorization are recorded
in [preparation responsiveness intent](../2026-10-16-preparation-responsiveness-test/intent.md).
The failed v0.0.54 tag remains unchanged; a future release uses a new version.
