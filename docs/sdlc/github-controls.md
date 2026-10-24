# GitHub controls required for the SDLC

These controls live outside the Git tree. Their absence is a release/process
gap even when repository CI is green.

## `main` ruleset

Enable an active ruleset targeting `main` with:

- pull requests required;
- at least one approval;
- code-owner review for the sensitive paths in `.github/CODEOWNERS`;
- approval of the most recent reviewable push;
- all review conversations resolved;
- required status check `SDLC Gate`;
- force pushes and deletions blocked;
- bypass limited to an explicit emergency role, with an audit reason.

The stable gate name lets internal CI jobs change without repeatedly editing
the ruleset.

## `production` environment

Create a `production` environment and configure:

- a required human reviewer;
- deployment branches/tags restricted to tags matching `v*`;
- no administrator bypass for routine releases;
- `APPLE_CERTIFICATE_P12` and `APPLE_CERTIFICATE_PASSWORD` as repository or
  environment secrets;
- `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD` when the certificate is
  a Developer ID identity.

The release workflow fails when the configured signing identity cannot be
imported or does not match the built app. Developer ID releases additionally
fail when notarization credentials or Apple acceptance are missing. The
existing project self-signed identity remains supported without being described
as Developer ID or notarized.

## Release operation

1. Merge a verified change through protected `main`.
2. Confirm the `SDLC Gate` result on the exact release commit.
3. Create an annotated `vMAJOR.MINOR.PATCH` tag on that commit.
4. Approve the protected `production` deployment.
5. Require mounted-DMG verification and the published SHA-256 checksum. For a
   Developer ID identity, also require successful Apple notarization and
   stapling.

An ad-hoc artifact is never a release. A project self-signed release is allowed
only through the explicit self-signed branch and must be labeled as not
Apple-notarized; it does not provide Developer ID trust or Gatekeeper acceptance.

## Periodic audit

Quarterly, and after any administrator change, verify the active ruleset,
environment reviewers, secret names, action permissions, and one dry-run release
candidate. Record the audit as a low-risk change bundle.
