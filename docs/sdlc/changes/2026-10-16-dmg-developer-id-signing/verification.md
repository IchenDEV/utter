# Verification: Sign the Developer ID distribution DMG

**Status:** approved
**Approved-by:** User, explicit chat reply to verification acceptance: 批准
**Approved-date:** 2026-10-16
**Upstream:** [Plan](plan.md)

## Current state

Local implementation and validation completed on `codex/fix-developer-id-dmg-signing`.
Intent, design, and execution plan have separate human approvals. No remote
source, tag, release, collaborator, or protection changes have been made during
this correction. Final independent verification passed with no findings.
The user accepted this verification on 2026-10-16 and authorized the PR stage.

## Implemented behavior

The shared workflow signs the Developer ID DMG with its exact imported identity,
secure timestamp, and dedicated container identifier before its first artifact
verification. The verifier rejects invalid container signatures, non-Developer
ID authorities, absent timestamps, and app/DMG certificate mismatches before
mounting. It also rejects failed or malformed certificate fingerprint decoding.
Self-signed and generic packaging paths retain their existing requirements.

## Local evidence

| Check | Result |
|---|---|
| Old workflow with new regression | Failed: unsigned DMG reached verification |
| Old verifier with new regression | Failed: invalid container cases were accepted |
| Fixed literal workflow contract | Pass, including signing failure stopping before verification |
| Actual verifier with controlled tool fixtures | Four tests pass, including invalid signatures, mismatch, missing timestamp, and generic packaging |
| `bash -n` | Pass for changed shell scripts; extracted workflow block executes under `bash -e` |
| `bash scripts/ci-basic-checks.sh` | Pass with installed Python 3.14.6 |
| Protected `swift test --skip-build` | Setup failure before tests: nested `sandbox_apply` denied |
| Complete native XCTest suites | 1,143 cases, 17 skipped, zero failures |
| Swift Testing | One unique case passed |
| Test input and bundle integrity | Swift/resources/package inputs match baseline; all 300 frozen files unchanged |
| Runtime canaries | Preference synchronization denied; real keychain file open denied with EPERM |
| Independent final verification | Pass, no findings; actual native verifier, complete test identities, hashes, and cleanup independently checked |
| Release-style local build | Pass, Developer ID app and complete DMG packaging |
| Actual shared workflow block on native App/DMG | Pass, signing then full artifact verification |
| Native unsigned DMG | Rejected at the new signature guard |
| Native signed DMG without secure timestamp | Rejected at the new timestamp guard |
| Native matching certificate without expected flag | Pass, app and DMG certificates still compared |
| Native DMG identity/fingerprint/timestamp | Pass, selected Developer ID and dedicated identifier |
| Temporary mounts | None remain |

The complete suites use all 14 frozen XCTest bundles. Thirteen Swift Testing
invocations contain no cases and return the expected exit 69; count only the
one unique passing Swift Testing case. The native results do not turn the
protected `swift test` wrapper failure into a command pass.

Public summaries and focused logs are in [evidence](evidence/). The full native
run is recorded in `evidence/full-test-evidence.json`. The
[final independent report](evidence/implementation-final-verification.json)
includes the code review, native verifier reruns, full-suite identity and hash
checks, and remaining human gates. The independent native commands are in
[native-independent-rerun.json](evidence/native-independent-rerun.json).

## Native artifact scope

`evidence/native-dmg-verification.json` records the exact commands and fixture
directory. The real local build uses Xcode 27.0, the existing Developer ID
identity, and version 0.0.54. Its app is copied into a task-owned fixture with
the unsigned DMG produced by the generic packager. The actual shared workflow
block signs that DMG and invokes the actual repository verifier successfully.
The verifier checks real signatures, owned resources, architectures, versions,
mounted app equality, and the matching certificate.

The selected certificate SHA-256 is
`1B499618154DEB0204896CDB199AA65D25EDA2188FEDBB0E29A73063728E4112`,
team `G9L7H3T3D5`. Native DMG metadata shows a secure timestamp and identifier
`com.opentype.voiceinput.dmg`. The local signed DMG SHA-256 is
`24765f7ce54b07cb7b1c9427d8e67cdbcf9df270e8011bb8d82e7e2049a89101`.
This checksum identifies a local verification fixture, not a published asset.

Unsigned and deliberately untimestamped copies fail at their intended guards.
Certificate mismatch uses controlled external-tool fixtures against the actual
verifier, both with and without the expected fingerprint argument. A second
native Developer ID identity was not used or claimed.

These new local fixtures have not been notarized, assessed by Gatekeeper as
notarized software, uploaded, or published. Apple acceptance from the earlier
failed v0.0.53 run does not establish those outcomes for this correction.

## Corrected validation setup

The first minimal PATH selected system Python 3.9.6, below the repository's
Python 3.10+ requirement. Basic checks failed in existing evaluator tests.
The launcher now selects installed Homebrew Python 3.14.6 and the complete
basic check passes. The first build was stopped before packaging to correct
the same PATH, then restarted using its cache. Initial logs are preserved.

The runtime-canary witness parser initially expected JSON, while the existing
canary binaries emit plain text. The parser was corrected before running the
full suite. Both canaries passed; no private runtime policy was weakened.

The first PR CI attempt rejected unittest separator lines in two newly tracked
raw evidence logs as conflict markers. The original logs remain unchanged
locally; lossless JSON copies preserve their contents and SHA-256 in the PR.
The conflict-marker guard and reviewed production/test code are unchanged.
`evidence/pr-ci-first-failure.json` preserves the exact run, job, and cause.

## Remaining gates

Human verification acceptance is complete. The remote PR stage is authorized.
An eligible human PR approval route and a new run-specific production approval
remain required.
The failed v0.0.53 tag and latest public v0.0.52 are preserved.

## Rollback

Revert the scoped source correction through a reviewed PR if needed. Preserve
existing credentials, protections, failed tags, and prior assets. No new public
release has been published by this correction.
