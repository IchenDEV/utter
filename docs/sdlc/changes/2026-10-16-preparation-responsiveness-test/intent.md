# Intent: Make the preparation responsiveness check deterministic

**Status:** approved
**Approved-by:** IchenDEV, explicit continuous scope authorization
**Approved-date:** 2026-10-16
**Upstream:** [Blocked v0.0.54 candidate](../2026-10-16-dmg-developer-id-signing/release.md)
**Risk:** Medium, test reliability and an internal instrumentation seam

## Problem and evidence

Release run `38861433092` completed 1,143 XCTest cases with 18 skips and one
failure at `Tests/OpenTypeTests/UtilityTests.swift:271`. The preparation
responsiveness test observed zero heartbeats. Swift Testing's one case passed;
the production job was skipped. No signing, notarization, or publication ran.

The same source passed local complete native tests and two exact-head CI runs.
The production function still executes preparation in `Task.detached`. The test
starts its probe after `Task.yield`, which does not guarantee that the probe
runs before fast preparation completes. A zero counter alone cannot distinguish
that race from real MainActor blocking. Do not rerun until green or remove the
responsiveness assertion.

## Proposed bounded design and execution

Reuse the existing path-scoped entry/exit barrier pattern used by startup
cleanup tests. Add optional, default-nil callbacks to the internal preparation
entry points, invoked inside the existing detached work around real preparation.
The test's MainActor observes worker entry before exit, then releases the
barrier. A detached watchdog prevents a broken MainActor implementation from
hanging the test. This removes assumptions about copy duration and task order.
Keep real file preparation and cleanup in the exercised path.

No app behavior, signing, credentials, dependency pins, main/production controls,
or UI changes are intended. Keep the change to the preparation test and its
internal callback plumbing. Do not grow the existing oversized test file.

## Acceptance and delivery

- Preserve the exact first CI failure, complete counts, and skipped production.
- The synchronized test passes with detached preparation and rejects a controlled
  synchronous-MainActor regression for the intended assertion, without hanging.
- Run the focused case and full local suites with refreshed complete bundles,
  hashes, and privacy canaries. Preserve native SwiftPM build sandboxing, fixed
  dependency pins, no dependency downloads, and at least 10 GiB free disk.
- Required SDLC/basic checks and release-style packaging pass. Independent
  verification confirms the assertions still prove responsiveness.
- Deliver through a PR with full CI, then merge under the owner's authorization
  and verify exact main CI before the next release candidate.
- Preserve failed v0.0.53 and v0.0.54 tags. Recheck and use the next unused stable
  version, expected v0.0.55. Keep a separate production decision for that run.

## Requested scope authorization

The owner may approve this intent together with the concrete design and work
above, authorizing continuous local implementation, validation, independent
review, PR, and merge when all checks pass, without repeated intermediate stage
questions for this bounded correction. Record that explicit authorization in
the subsequent stage artifacts. A failed check or material scope change still
stops progression. Production approval is not included.

## Rollback

Revert this scoped test/instrumentation change through a PR. Preserve the full
responsiveness requirement, failed tags and first-failure records. Do not loosen
CI, signing, Gatekeeper, checksum, or production approval to publish.

The owner answered "批准此范围连续修复并合并" to the bounded scope above.
This authorizes intent, design, execution, verification, and merge after checks
pass. It does not authorize production for a future release run.
