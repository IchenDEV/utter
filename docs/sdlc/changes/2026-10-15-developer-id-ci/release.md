# Release: Utter v0.0.53 with Developer ID

**Status:** approved
**Approved-by:** User, explicit decision for run 38770474797: 批准本次 production 发版
**Approved-date:** 2026-10-16
**Upstream:** [Verification](verification.md)
**Risk:** High, public software distribution

## Authorization and candidate

The user requested "帮我发版" on 2026-10-16 after receiving the configuration
verification. Use the existing tag release workflow and retain GitHub's human
`production` approval. The user explicitly approved production for run
`38770474797` on 2026-10-16. The agent submits that human decision to GitHub;
the independent verifier does not supply the approval.

- Candidate: `f0ef2aa88296da017e29ced2b7bc9271af96e4fb`, current `origin/main`.
- Next version: `v0.0.53`. Latest published release is `v0.0.52`.
- Product and workflow source are unchanged. This release changes distribution
  signing to the configured Developer ID identity and Apple notarization.
- Existing local SDLC evidence remains untracked and outside the release tag.

## Preconditions

- The candidate's `SDLC Gate`, `Contract & Tests`, and `Release-style App Build`
  checks passed in PR workflow run `38089004676`.
- Complete local native suites passed on this exact source as recorded in
  verification. The protected `swift test` wrapper limitation remains disclosed.
- Version syntax is valid. No remote `v0.0.53` tag or release exists.
- Production requires human reviewer `IchenDEV`, disallows administrator
  bypass, and restricts deployments to `main` and `v*`.
- All five approved signing and notarization secret names exist in production.
- Initial preflight found `main` unprotected with its ruleset disabled. The
  user explicitly chose "先启用 main 分支保护" on 2026-10-16. Activation
  completed; a fresh GitHub read reports `protected: true` and all required
  effective rules. The candidate SHA is unchanged.

## Approved branch-protection prerequisite

Reuse ruleset `14695153` with `enforcement: active`, target exactly
`refs/heads/main`, and no bypass actors. Retain deletion and force-push
prohibitions. Add the existing repository contract's PR requirements: one
approval, code-owner review, dismissal of stale approvals, approval of the
latest push, and resolved review threads. Require current `SDLC Gate` from
GitHub Actions integration `15368` with strict up-to-date checks.

Save the original ruleset and the live result. Read both the effective rules
and `branches/main.protected` before tag creation. This operation changes
repository protection settings only. The user's explicit prerequisite request
authorizes this addition to the release preparation.

The mutation and readback passed. Public before/request/after records and
effective rules are saved as `evidence/main-*.json`. Refreshed local SDLC and
basic CI checks passed. No bypass role was added.

## Execution and acceptance

Create an annotated tag on the exact candidate and push only that tag. The
workflow reruns repository checks and `swift test` before waiting for production
approval. Signing, notarization, stapling, Gatekeeper, mounted-DMG, checksum, and
download equality checks must succeed before publication.

Retain the workflow URL, tag object and commit, Apple notarization result,
certificate and team, published asset checksum, and independent final review.
No tag, asset, credential, or protection is replaced on failure. Diagnose any
failure before proceeding.

## Rollback

Keep `v0.0.52` and its assets intact. If the new release is defective, remove it
from the latest recommendation and restore `v0.0.52` as latest with clear
notice that the prior version is not Apple-notarized. Preserve failure evidence
and open a corrective change. Never move the tag or replace same-version assets.

## Current state

Independent readiness review and refreshed local repository checks passed.
Main protection activation passed independent remote confirmation.

Annotated tag `v0.0.53` was pushed and read back successfully. Its tag object is
`b8e869cddca904cd525ece4fcb36d55fd4a14a33`; its peeled commit is exactly the
candidate SHA. Public evidence is `evidence/release-tag.json`.

[Release run 38770474797](https://github.com/IchenDEV/utter/actions/runs/38770474797)
started on that candidate. Release Candidate Tests passed. The actual CI log
records 1,143 XCTest cases, 18 conditional skips, zero failures, and one Swift
Testing case passed. Repository checks, version/main validation, and Metal
toolchain setup also passed. This CI `swift test` result is separate from the
earlier local wrapper limitation.

The protected `production` deployment waited for required reviewer
`IchenDEV`. Its environment ID is `20910208532`; bypass is disabled. The log and pre-approval API
responses are retained in `evidence/release-candidate-tests.log`,
`evidence/release-jobs-before-approval.json`, and
`evidence/release-pending-deployment.json`.

Independent pre-production verification passed and is recorded in
`evidence/release-before-production-independent.json`. The verifier matched
all 1,143 XCTest starts and completions. The one extra skip compared with the
local run is `DeferredReplacementPolicyTests.testDecisionRequiresSameFrontmostApp`:
the CI test process has no bundle identifier. That case passed locally.

The user answered "批准本次 production 发版" to the question naming this exact
run, candidate test results, version, and production deployment. The agent
submitted that decision to GitHub, which records approval by `IchenDEV` for the
production environment. Deployment ID is `7098728919`. Public request-source,
response, and readback records are `evidence/release-human-production-authorization.json`,
`evidence/release-production-approval-response.json`, and
`evidence/release-production-approval-readback.json`.

## First execution result

The run completed with failure before publication. Candidate tests, Developer
ID app signing, certificate fingerprint checks, and mounted-DMG app equality
passed. Apple accepted submission `29a24fa6-d6b6-4053-9213-a9989e6e705a`.
Stapling and subsequent ticket validation passed.

The DMG Gatekeeper assessment then returned `rejected`,
`source=no usable signature`, exit 3. Packaging signs the App but not the outer
DMG. `Publish GitHub Release` was skipped. GitHub reports no v0.0.53 release and
no retained workflow artifacts; latest remains v0.0.52. The failed tag remains
unchanged. Do not blindly rerun or weaken distribution verification.

The signing log is `evidence/release-signing-attempt-1.log`; complete job states
are `evidence/release-jobs-attempt-1.json`. Independent diagnosis agrees that the
outer DMG needs Developer ID signing before notarization. The failed artifact
is unavailable for direct byte-level reinspection.

[Corrective intent](../2026-10-16-dmg-developer-id-signing/intent.md) records the
minimal follow-up scope. It awaits human intent approval before design and
implementation under the repository's strict stage contract.
