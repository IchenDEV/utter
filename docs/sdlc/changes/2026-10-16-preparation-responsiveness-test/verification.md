# Verification: Deterministic preparation responsiveness

**Status:** approved
**Approved-by:** IchenDEV, explicit continuous scope authorization after passing checks
**Approved-date:** 2026-10-16
**Upstream:** [plan](plan.md)

## Local result

The synchronized preparation test passes with a tiny real fixture. Forcing the
whole worker closure onto MainActor produces exactly the intended responsiveness
assertion failure, with one failed XCTest and no hang. The harness exit is zero
because it confirmed that expected failure. The original source was restored
byte-for-byte and tests rebuilt; the restored case passes.

Both the complete frozen native engines and protected `swift test --skip-build
--skip-update --disable-automatic-resolution` pass all 1,143 unique XCTest cases
with 17 conditional skips and no failures, plus one Swift Testing case. Discovery
identities exactly match every started and finished case across all 14 bundles.
All 702 frozen product files, including 300 bundle files and sibling resources,
retain their hashes. Package.resolved retains its original 19 pins and hash.

The first protected wrapper omitted the isolated user directory and encountered
four assertions in one existing catalog test. The corrected isolated wrapper
then failed before tests because SwiftPM's uncached manifest required a nested
sandbox. Precompiling that same isolated-home manifest outside the runtime policy
resolved the wrapper setup. Native SwiftPM sandboxing and the runtime privacy
policy stayed enabled. See [first failures](evidence/first-failures-and-resolution.json).
No unrelated product code was changed to make the wrapper pass.

`bash scripts/sdlc-checks.sh` and `bash scripts/ci-basic-checks.sh` pass. The actual
release-style build for local version 0.0.55 passes App Developer ID signing,
resource checks, DMG checksum and mounted-content verification. This local
fixture is not notarized, published, installed, or launched. Production remains
separately protected.

## Safety and scope

Runtime canaries confirm denied real preferences/keychain paths and the isolated
test home. Build and test processes use a minimal environment without inherited
API credentials. Raw logs remain private; public evidence contains summaries,
hashes, repository-relative names, and redacted machine paths.

A byte-verified relocation preserved the complete build cache and dependency
checkouts on a local APFS volume. The original logical build path remains a
symlink. The release-build guard stopped an attempted start below 10 GiB free;
work resumed only after space recovered. No user applications, data, credentials,
or session history were removed.

## Delivery

Independent final local review passed. See [independent report](evidence/independent-local-review.json). The owner explicitly authorized continuous
local verification and PR merge once checks pass. Exact-head PR CI and exact-main
CI remain required before a new immutable release tag. Failed v0.0.53 and v0.0.54
remain unchanged. Production authorization is outside this scope.

Revert this scoped source/test change through a PR to roll back. Restore a timing
assumption only with equivalent deterministic responsiveness coverage; do not
relax signing, CI, Gatekeeper, checksum, or production controls.

The owner answered "批准此范围连续修复并合并" for this bounded correction.
All required local verification conditions above are now met; this records that
explicit conditional authorization, not agent-generated human approval. PR
merge remains conditional on exact-head CI, and production is excluded.
