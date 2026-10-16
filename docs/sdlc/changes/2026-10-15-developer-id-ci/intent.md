# Intent: Configure Developer ID signing for CI

**Status:** approved
**Approved-by:** User, explicit chat reply: 批准
**Approved-date:** 2026-10-15
**Upstream:** User request on 2026-10-15: 帮我配置CI，支持公签
**Risk:** High, signing credentials and release configuration

## Problem

The release workflow already supports Developer ID signing and Apple
notarization, but its GitHub configuration lacks notarization credentials.
The supplied `Apple Developer.p12` contains an Apple Development certificate,
which cannot satisfy the workflow's Developer ID distribution requirement.

## Outcome

Tag releases and nightly releases use a Developer ID Application identity,
receive Apple notarization, staple the DMG, and pass the existing distribution
checks before publication.

## Scope

- Reuse `.github/workflows/release-artifact.yml` for both release entry points.
- Configure the five existing `APPLE_*` secrets in the `production` environment.
- Obtain a PKCS#12 export of the intended Developer ID Application identity.
  The local keychain contains `Developer ID Application: Chen Li (G9L7H3T3D5)`.
  Confirm this identity with the user before exporting its private key.
- Validate the certificate, matching private key, Apple team, and notarization
  credentials before activating the configuration.
- Record local checks and GitHub results separately. A production release
  requires its own authorization.

## Constraints

- Collect passwords through local hidden input. Keep passwords, private keys,
  PKCS#12 contents, and notarization credentials out of chat, logs, and Git.
- Preserve existing repository secrets. Environment secrets can override them
  without destroying the current configuration.
- Do not change workflow code unless credential configuration proves
  insufficient. Any required code change returns to reviewed design and plan.
- Never fall back to ad-hoc signing after a signing or notarization failure.
- Do not create tags, publish releases, or dispatch a publishing workflow as a
  credential test without explicit production authorization.
- The `production` environment currently has no required reviewers or tag
  restrictions. Secret configuration alone does not establish those controls.
- Follow the repository's per-stage human approval contract.

## Acceptance criteria

- The selected PKCS#12 contains a valid Developer ID Application certificate
  and its matching private key. Record only public identity metadata.
- The certificate's team matches `APPLE_TEAM_ID`, and Apple accepts the
  notarization credentials through a read-only `notarytool` request.
- `production` contains `APPLE_CERTIFICATE_P12`,
  `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, and
  `APPLE_APP_PASSWORD`. Preserve existing repository secrets.
- Both release entry points continue to inherit secrets and use the existing
  `production` job. The release workflow contract test passes.
- Before implementation handoff, record `sdlc-checks.sh`,
  `ci-basic-checks.sh`, and `swift test` results, plus risk-specific validation.
  Mark unavailable checks explicitly.
- Claim successful public distribution only after an authorized GitHub run
  proves signing, notarization, stapling, Gatekeeper assessment, mounted-DMG
  verification, and checksum verification.

## Initial evidence

- Checkout: `main` at `f0ef2aa88296da017e29ced2b7bc9271af96e4fb`.
- The local reusable workflow matches GitHub's current file byte for byte.
- `bash scripts/tests/test_release_workflow_contract.sh` passed.
- The supplied PKCS#12 was opened with a local hidden password prompt.
  Its certificate is Apple Development and expires on 2027-10-05.
  No password was retained and no private key was exported.
- The local Developer ID Application certificate expires on 2027-11-14.
  Its ability to export the private key remains unverified.
- GitHub repository secrets contain the two certificate secret names.
  Their values cannot be read through GitHub and were not inspected.
- No `production` environment secrets are currently configured.
- GitHub reports no `production` protection rules and allows admin bypass.
- No workflow code, GitHub secrets, or release settings have been changed.

## Rollback requirement

Keep existing repository secrets intact. If environment secrets are added,
record exactly which names were created so they can be removed to restore the
previous secret selection. Stop publishing while credentials are incomplete.

## Resolved questions

- The user approved this intent and use of the named local Developer ID
  Application identity on 2026-10-15.
- The user supplied Apple notarization credentials through local input on
  2026-10-16. Apple accepted the read-only authentication request.
- Production protection follows the separately approved design. Configuration
  is complete; production release authorization remains separate.

## References

- [Apple Developer ID distribution](https://developer.apple.com/developer-id/)
- [GitHub reusable workflow environment secrets](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-inputs-and-secrets-in-a-reusable-workflow)
