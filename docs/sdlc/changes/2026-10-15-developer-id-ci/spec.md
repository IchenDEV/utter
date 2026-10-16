# Spec: Configure Developer ID signing for CI

**Status:** approved
**Approved-by:** User, explicit chat reply: 批准
**Approved-date:** 2026-10-15
**Upstream:** [Intent](intent.md)

## Context

Both release entry points call `release-artifact.yml` with `secrets: inherit`.
Its signing job uses the `production` environment and already verifies
Developer ID signatures, notarization, stapling, and distribution artifacts.
Credential configuration is sufficient unless validation identifies a defect.

The public repository currently has no production reviewers or deployment
restrictions. Both release entry points are active. No incomplete workflow
runs were visible during the initial inspection. Recheck before mutation.

## Certificate and credentials

Use only the approved local identity:

- Name: `Developer ID Application: Chen Li (G9L7H3T3D5)`.
- Team: `G9L7H3T3D5`.
- Certificate SHA-256:
  `1B499618154DEB0204896CDB199AA65D25EDA2188FEDBB0E29A73063728E4112`.

Select that identity by its certificate fingerprint through macOS Security
APIs. Export that identity as password-protected PKCS#12 with a generated
password. Do not export every identity or change login-keychain trust or
private-key access permissions. If macOS denies export, stop and request a
PKCS#12 export of this Developer ID identity.

Collect the Apple ID and its app-specific password through local input. Check
the credentials with a read-only `notarytool history` request for the selected
team. Do not upload an app or expose submission history in the evidence.
Keep credentials out of command arguments and captured terminal output.

Any temporary PKCS#12 file has mode `0600` inside a private temporary directory.
Use an isolated temporary keychain for import and signing checks. Restore the
original keychain search list if a check changes it. Delete temporary secrets
and the temporary keychain on completion or failure.

## Production approval

Before configuring secrets, set the `production` environment to require the
repository owner `IchenDEV` as reviewer, and disable administrator bypass.
Allow the owner to approve their own triggered run so the single-owner
repository can release. The independent verification requirement remains.

Allow only branch `main` and tags `v*`. Nightly runs enter the environment with
`refs/heads/main` and create a tag inside the protected job. A tags-only
environment would block nightly before that step. Existing SemVer and
main-ancestry checks continue to constrain release artifacts.

Recheck active release runs after setting the approval gate. Stop before
changing secrets if a signing or publishing job is already running. Do not
approve a waiting production job during configuration. No publishing workflow
is dispatched by this change.

## Secret configuration

Write these names only in `production`, using `gh secret set` through standard
input. Preserve the existing repository-level secrets.

| Secret | Value source |
|---|---|
| `APPLE_CERTIFICATE_P12` | Base64 of the approved identity's PKCS#12 export |
| `APPLE_CERTIFICATE_PASSWORD` | Generated export password |
| `APPLE_ID` | User's Apple ID entered locally |
| `APPLE_TEAM_ID` | Verified certificate team `G9L7H3T3D5` |
| `APPLE_APP_PASSWORD` | User's app-specific password entered locally |

Finish all local validation before writing secrets. Recheck that no same-name
environment secrets appeared since inspection. If any appeared, stop rather
than overwrite values that GitHub cannot return for rollback.

Record each successful write by secret name only. Read back environment
metadata and secret names after configuration. GitHub cannot return secret
values, so their presence alone does not prove a successful signed CI build.

## Failure containment and rollback

Wrong identity, missing private key, failed import, failed signature check,
team mismatch, or rejected notarization credentials stop before secret writes.
Cancellation has the same effect. Do not use the supplied Apple Development
PKCS#12 as a substitute.

If a secret write fails, remove only the environment secrets created by this
attempt. Preserve the production approval gate and report cleanup failures.
The previous repository secrets then supply the original credential values.
Save the previous environment settings as public metadata. Restoring weaker
production protection requires a separate explicit human decision.

Workflow source remains unchanged. Any defect that requires a code change
returns to design review before implementation.

## Verification

- Check the exported certificate fingerprint, validity, team, and matching
  private key. Import into the temporary keychain and sign a disposable local
  executable. Verify its signature, certificate fingerprint, and team.
- Verify Apple accepts the notarization credentials through the read-only
  request. Report authentication success without history contents.
- Run the required SDLC checks, basic repository checks, Swift tests, and the
  release workflow contract test. Record failures or unmet prerequisites.
- Read back production reviewers, bypass policy, branch and tag rules, and all
  five secret names. Check that repository secret metadata is unchanged.
- Obtain independent verification of the risk-critical evidence before
  implementation handoff. A verifier does not approve production.
- A real GitHub signing, notarization, and Gatekeeper result remains unverified
  until a separately authorized release run completes.

## Approval boundary

This design does not begin implementation. After human design approval,
prepare the implementation plan and obtain its required approval before
exporting keys, collecting notarization credentials, or changing GitHub.

## References

- [GitHub environment protection and deployment ref rules](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [Apple keychain import and export APIs](https://developer.apple.com/documentation/security/keychain-items)
