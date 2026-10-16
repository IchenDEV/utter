# Intent: Sign the Developer ID distribution DMG

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准修复意图
**Approved-date:** 2026-10-16
**Upstream:** [Failed v0.0.53 release](../2026-10-15-developer-id-ci/release.md)
**Risk:** High, release signing and distribution

## Problem

The authorized v0.0.53 release run `38770474797` passed complete candidate
tests, Developer ID app signing, Apple notarization, and ticket stapling. It
stopped at the DMG Gatekeeper check with `source=no usable signature`, exit 3.
Nothing was published; the latest public release remains v0.0.52.

The packaging script signs Utter.app but creates the outer DMG without signing
it. The release verifier assesses the DMG's primary signature after checking
its notarization ticket. Independent review confirmed that missing container
signature explains this failure. No evidence points to notarization latency.

## Outcome

The existing CI pipeline publishes a Developer ID-signed and Apple-notarized
DMG whose own signature, embedded app, ticket, Gatekeeper assessments, and
published checksum all pass. The self-signed release path remains explicit.

## Scope

- Sign the Developer ID distribution DMG before its notarization submission.
- Verify the DMG uses the intended Developer ID certificate and timestamp.
- Add a focused regression control for the missing DMG-signing step and its
  failure path; keep the real Gatekeeper gate.
- Deliver the fix through a reviewed PR and protected main, then use a new
  release version for a separately identified production run.

## Constraints

- Keep failed tag `v0.0.53` at tag object
  `b8e869cddca904cd525ece4fcb36d55fd4a14a33`, peeled commit
  `f0ef2aa88296da017e29ced2b7bc9271af96e4fb`. Do not move or delete it.
- Preserve v0.0.52, existing assets, configured credentials, main protection,
  and human production approval. Never replace same-version published assets.
- Stop when configured signing fails. No ad-hoc fallback, Gatekeeper bypass,
  or delay-only workaround.
- Do not change app behavior, permissions, bundle identifiers, or dependencies.
- Follow intent, design, plan, verification, PR, and production human gates.

## Acceptance criteria

- A regression check fails against the current missing-signature behavior and
  passes with the fix. Signing failure stops before notarization/publication.
- The generated Developer ID DMG's certificate matches the approved app
  certificate SHA-256
  `1B499618154DEB0204896CDB199AA65D25EDA2188FEDBB0E29A73063728E4112`.
- Appropriate local repository checks, complete tests, and release-style
  packaging pass, with unavailable checks disclosed separately.
- Independent verification confirms the change, rollback, and actual results.
- A new approved CI run receives Apple acceptance, staples the ticket, passes
  both DMG and app Gatekeeper checks, and publishes a checksum-verified download.

## Evidence and rollback

The original signing log, job status, and independent failure analysis are in
`../2026-10-15-developer-id-ci/evidence/`. Apple accepted submission
`29a24fa6-d6b6-4053-9213-a9989e6e705a`; that is notarization evidence only.
The failed run exposes no retained downloadable artifact. No release or assets
exist for v0.0.53, so no public artifact needs rollback. Revert the scoped fix
through a PR if necessary, preserving the failed tag and release evidence.

## Open questions

The user approved intent, [design](spec.md), [plan](plan.md), and
[local verification](verification.md) on 2026-10-16. PR approval and the new
run-specific production decision remain required.

## References

- [Failed release run](https://github.com/IchenDEV/utter/actions/runs/38770474797)
- [Apple packaging requirements](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
