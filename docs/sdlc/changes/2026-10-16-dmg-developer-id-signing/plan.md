# Plan: Sign the Developer ID distribution DMG

**Status:** approved
**Approved-by:** User, explicit chat reply to implementation plan: 批准
**Approved-date:** 2026-10-16
**Upstream:** [Spec](spec.md)

## Baseline and scope

Intent, design, and this plan have explicit human approvals. The user approved
this plan on 2026-10-16. Keep the failed v0.0.53 tag and its first-run
evidence intact. Current public latest remains v0.0.52.

The production change is limited to the shared release workflow and existing
artifact verifier. Extend the existing workflow contract test; add a focused
script under `scripts/tests/` only if needed to keep files below 300 lines.
Do not change app source, dependencies, credentials, code owners, or protections.

## Work items

- [x] Record current HEAD, branch, tracked/index/untracked changes, source and
  `Package.resolved` hashes, and available disk. Preserve existing SDLC bundles.
  Use a `codex/` fix branch in this checkout when safe so existing build caches
  can be reused. Stop on unexpected owner changes; do not reset or overwrite.
- [x] Extend the existing contract harness to run the actual extracted
  classification/signing block in an external `bash -e` process. Its fixture
  models signing state and records command order without credentials or remote
  writes. Prove the new regression fails against the old unsigned-DMG block in
  a disposable baseline copy before changing production code.
- [x] In `.github/workflows/release-artifact.yml`, add native DMG signing in the
  existing Developer ID branch before its first verifier call. Use exact
  `SIGN_IDENTITY`, `--timestamp`, and identifier `com.opentype.voiceinput.dmg`.
  Keep the existing self-signed branch and all publication gates.
- [x] In `scripts/verify-release-artifact.sh`, when a DMG and
  `--require-developer-id` are supplied, verify the DMG's own strict signature,
  Developer ID authority, secure timestamp, and certificate equality with the
  app and optional expected fingerprint. Reuse certificate extraction. Reject
  before mounting or notarization; retain existing post-staple checks.
- [x] Complete contract cases for successful sign-before-verify order, signing
  failure before any verifier/submission progression, and the self-signed
  branch. Invoke the extracted block as a separate `bash -e` command so shell
  conditional contexts cannot suppress the production error behavior.
- [x] Build a release-style local app and DMG using the existing build script
  and approved available Developer ID identity. Use task-owned output copies
  for native verification; keep private key material in the existing keychain.
  No new identity export or notarization credential is needed for these checks.
- [x] Run the actual verifier on the real app plus disposable DMG variants:
  signed/timestamped success, unsigned rejection, and missing-timestamp
  rejection. Record the exact diagnostic so a prior unrelated failure cannot
  masquerade as reaching the new container guard.
- [x] Verify the fingerprint-mismatch branch, including invocation without
  `--expected-cert-sha256`. Use a controlled external-tool fixture if a second
  real Developer ID identity is unavailable. Run the actual verifier, and label
  this as fixture coverage rather than a second native signing identity.
- [x] Run required local repository/full-suite checks and release packaging
  checks as detailed below. Preserve first failures and resolve findings within
  the approved scope. Keep `Package.resolved` unchanged.
- [x] Obtain independent read-only verification of the actual diff, regression
  old-fail/new-pass evidence, native verifier results, and cleanup. Address its
  actionable findings before presenting implementation verification.
- [x] Record commands, outcomes, skips, evidence paths, rollback, and remaining
  release gates in `verification.md`. Set it to `pending approval` and stop for
  the human verification decision before starting the remote PR stage.

## Verification plan

- [x] `bash -n` for changed shell scripts and extracted workflow shell blocks.
- [x] `bash scripts/tests/test_release_workflow_contract.sh`, including the
  observed regression and fail-closed cases. The baseline run must fail for the
  missing DMG signing operation, rather than fixture setup.
- [x] Any focused verifier fixture test added under `scripts/tests/`, including
  missing signature, certificate mismatch, and missing secure timestamp.
- [x] `bash scripts/sdlc-checks.sh`.
- [x] `bash scripts/ci-basic-checks.sh`.
- [x] Complete local Swift test suites with all discovered test identities and
  final completion accounted for. Preserve the distinction between a command
  wrapper failure and actual test results.
- [x] Release-style packaging through `bash scripts/build-app.sh`, followed by
  the approved shared signing block and real verifier on task-owned copies.
- [x] Native signature/certificate/timestamp inspection plus verifier positive
  and negative cases. Retain public metadata and logs, never private keys or
  credentials. Detach only task-owned mounts and confirm cleanup.
- [x] Independent implementation verification and fresh SDLC/diff checks.

### Complete local test execution

The previous protected `swift test` wrapper failed before execution because of
nested `sandbox_apply`. Complete native XCTest and Swift Testing runs passed.
Use the already validated runtime approach; do not weaken the runtime policy
or disable SwiftPM's native sandbox as a workaround.

Before reusing the complete frozen bundles, verify that current Swift sources,
package configuration, resources, and bundle hashes still match their build
inputs. If they differ, build the tests outside the private runtime policy
with native SwiftPM sandboxing, then freeze the complete bundles and hashes.
Run only test processes under the validated policy with a minimal environment.
Recheck its preference/keychain canaries and complete identity coverage.

Keep the original wrapper setup failure visible. If recording a fresh standard
wrapper attempt, stop after the same setup failure and use the complete native
engines; do not start another sandbox-workaround search. A fresh CI `swift test`
must pass on the exact PR/merged candidate before production.

Check disk before each heavy build and retain at least 10 GiB free. Verify the
lockfile hash after Swift/Xcode commands. Stop on unplanned dependency changes
or insufficient disk; preserve source and evidence rather than broad cleanup.

## Human gates and release sequence

The user's separate decisions approved intent and design on 2026-10-16.
Approval of this plan authorizes the listed local implementation, signing
fixtures, required tests, and independent review. It does not supply later
verification acceptance, PR approval, or a new production decision.

After human verification acceptance, push the scoped fix branch and open a
reviewable PR. Attach that PR to this task and verify its remote SHA and CI.
Main currently has one collaborator/code owner and requires an independent
approving review. Resolve an eligible human approval route for that concrete
PR before merge. Do not add collaborators, alter code owners, or bypass rules
under this plan.

After the protected merge, verify the exact merged SHA's `SDLC Gate`, recheck
tags/releases and main, and select the next unused stable version, expected
v0.0.54. Never move v0.0.53. Trigger its normal release tests and request a
separate human production decision for that specific run.

The authorized production run must show accepted Apple notarization, stapling,
DMG and app Gatekeeper acceptance, mounted-app equality, and published checksum
and download equality. Independently download and verify the published asset
before claiming the release complete.

## Stop conditions and rollback

Signing, timestamp, fingerprint, verifier, test, or packaging failure stops
progression to the remote PR/release stage until corrected or explicitly
reviewed. Preserve exact missing prerequisites and failure evidence. No ad-hoc
fallback, gate removal, or blind release retry is allowed.

Revert a defective scoped fix through a PR. Preserve protections, credentials,
failed tags, and older assets. If a published release needs withdrawal, restore
the previous latest recommendation without replacing assets, and disclose the
older release's signing status. No public artifact requires rollback now.
