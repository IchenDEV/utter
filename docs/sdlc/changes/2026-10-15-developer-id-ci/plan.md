# Plan: Configure Developer ID signing for CI

**Status:** approved
**Approved-by:** User, explicit chat reply: 批准
**Approved-date:** 2026-10-15
**Upstream:** [Spec](spec.md)

## Work items

- [x] Recheck the checkout, approved certificate fingerprint, GitHub admin
  access, and both release entry points. Save production settings, deployment
  rules, workflow states, and repository secret metadata as public evidence.
- [x] Confirm that the five target environment secrets are absent. Stop if
  another actor has created any of them. Never overwrite an unknown value.
- [x] Export only the approved Developer ID identity through macOS Security
  APIs, with a generated password and private temporary storage. Stop on export
  denial without changing key permissions or using a different identity.
- [x] Import the export into a temporary keychain. Sign a disposable executable
  and verify its signature, certificate fingerprint, team, and hardened runtime.
  Retain the signed executable as public verification evidence.
- [x] Collect the Apple ID and app-specific password through local input.
  Authenticate a read-only `notarytool history` request for `G9L7H3T3D5`.
  Suppress credentials and submission history in all recorded output.
- [x] Run the local checks below. Stop before remote mutation if a required
  check fails or a prerequisite is unavailable.
- [x] Configure production review by `IchenDEV`, allow owner approval of their
  own runs, disable administrator bypass, and restrict deployment to branch
  `main` and tags `v*`. Read back the settings before proceeding.
- [x] Recheck all incomplete release runs, including queued and waiting runs.
  Stop before secret writes if a signing or publishing job is already running.
  Leave waiting deployments unapproved throughout configuration.
- [x] Recheck secret absence, then write the five secrets from the approved
  spec through `gh secret set` standard input. Record successful names only.
  Preserve repository secrets and workflow source.
- [x] Read back environment protections, deployment rules, and all five secret
  names. Compare repository secret metadata and workflow source with the saved
  baseline. Report remote API results separately from local test results.
- [x] Delete temporary private material and the temporary keychain. Restore
  the keychain search list if changed. Keep only public verification artifacts.
- [x] Obtain a fresh-context, read-only independent verification of the
  configuration and evidence. Resolve findings within the approved scope.
- [x] Record results and remaining release evidence gaps in `verification.md`.
  Set its status to `pending approval` for the human verification decision.

## Verification plan

- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test` attempted. Its protected wrapper failed before tests;
  the complete native test suites passed as recorded below.
- [x] `bash scripts/tests/test_release_workflow_contract.sh`
- [x] Check the exported PKCS#12 certificate against the approved fingerprint
  and validity dates. Prove its private key works by signing the disposable
  executable with the isolated imported identity.
- [x] Run `codesign --verify --strict` and inspect the signed executable's
  certificate, team, and hardened runtime flags. The independent verifier
  repeats these checks on the retained public executable.
- [x] Confirm notarization authentication succeeds without uploading software.
- [x] Query GitHub to prove reviewer, bypass, deployment rules, and secret-name
  configuration. Confirm the repository credential metadata is unchanged.
- [x] Independently verify both callers still inherit secrets and their shared
  signing job still targets `production`.

## Failure and rollback

Local validation failure or user cancellation leaves GitHub unchanged. A
remote failure stops subsequent writes. Remove only the environment secrets
created by this attempt, and verify their removal. Keep the new production
approval gate and report any cleanup failure. Repository secrets remain the
fallback after environment secrets are removed. Restoring weaker production
protection requires separate human authorization.

## Human gates

Intent and design are approved by the user's separate chat replies on
2026-10-15. The user also approved this plan on 2026-10-15. Execute the listed
configuration and validation work without further per-operation confirmation.
The user supplied credentials locally. The approved configuration is complete.
Human verification acceptance remains pending.

Human verification approval, any required PR approval, and production approval
remain separate. Do not create a release tag, dispatch a publishing workflow,
approve a waiting production deployment, or publish a release under this plan.
Actual CI signing, Apple notarization, stapling, Gatekeeper assessment, and
mounted-DMG results require a separately authorized release run.

## Execution evidence

Completed on 2026-10-16. See [verification](verification.md). The protected
SwiftPM test wrapper failed before tests, so all 14 complete bundles ran through
the native XCTest and Swift Testing engines under the corrected runtime policy.
An independent verifier matched all discovered test identities and final suite
completion. The complete suite has zero behavioral failures. The wrapper setup
failure remains recorded separately. No product or workflow source was changed.
