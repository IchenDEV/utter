# GitHub controls required for the SDLC

These controls live outside the Git tree. Their absence is a release/process
gap even when repository CI is green.

## `main` ruleset

This repository currently has one developer. Keep an active ruleset targeting
`main` with:

- pull requests required;
- zero required approving reviews, without mandatory code-owner or last-push
  approval; the sole developer cannot provide a separate reviewer identity;
- all review conversations resolved;
- required status check `SDLC Gate`;
- force pushes and deletions blocked;
- no bypass actors.

The owner explicitly authorizes merge after reviewing the change and its
evidence. High-risk changes still require independent technical verification.
`CODEOWNERS` continues to document ownership. If another maintainer joins,
review whether separate approving reviews should become mandatory.

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
  a Developer ID identity;
- `SPARKLE_ED_PRIVATE_KEY`, the Sparkle EdDSA private key, whenever the release
  carries update metadata.

The release workflow fails when the configured signing identity cannot be
imported or does not match the built app. Developer ID releases additionally
fail when notarization credentials or Apple acceptance are missing. The
existing project self-signed identity remains supported without being described
as Developer ID or notarized.

### Updater key ceremony and rotation

The agent never handles the private key; the owner runs the ceremony:

1. Download the pinned Sparkle tools (see `scripts/sparkle-tools.sha256`), run
   `generate_keys`, and keep the private key in the login keychain.
2. `generate_keys -x key.txt`, then
   `gh secret set SPARKLE_ED_PRIVATE_KEY --env production < key.txt`, then delete
   `key.txt` and keep an offline backup. GitHub is the only copy on the network.
3. Give the agent only the public key (`generate_keys -p`); it is committed to
   `Resources/UpdateInfo.plist`.

The pipeline fails closed when the secret is missing, and the independent
CryptoKit check in the `Sign update metadata` step fails when the secret does
not match the committed public key. Because Sparkle accepts either a valid
EdDSA signature or a matching Developer ID signature, rotation is a release
signed with Developer ID that carries a new `SUPublicEDKey`; the quarterly audit
below confirms the secret still exists.

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

Every release also publishes `appcast.xml` beside the DMG. The pipeline signs the
DMG and the feed with `SPARKLE_ED_PRIVATE_KEY` and then re-verifies both with
`scripts/verify-update-signature.swift` against the public key inside the DMG, so
a wrong or rotated secret fails before the draft is published. The appcast and
the DMG become reachable in the same `--draft=false --latest` step; every release
carries its own immutable one-item feed.

## Updater feed operation

- **Withdraw a bad release:** `gh release edit <bad> --prerelease` and
  `gh release edit <good> --latest`. Clients on older versions are offered the
  good release again. Clients already on the bad version see nothing newer and
  are fixed forward with a higher version. Nothing is deleted and no asset is
  replaced.
- **Code rollback:** revert the update integration in a normal PR; already
  installed copies keep polling the feed, so withdrawal above is the control
  point that decides what they are offered.
- **Rotation:** see the key ceremony above. A Developer ID signed release can
  carry a new `SUPublicEDKey`.
- **First updater release:** users install it manually once. Only the release
  after it is the first real in-app update, and permissions, launch-at-login and
  restart behavior are observed on a real Developer ID install.

## Periodic audit

Quarterly, and after any administrator change, verify the active ruleset,
environment reviewers, secret names (including that `SPARKLE_ED_PRIVATE_KEY`
still exists), action permissions, and one dry-run release candidate. Record
the audit as a low-risk change bundle.
