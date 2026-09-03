# Intent: Fix OpenSSL 3 PKCS#12 import so releases can ship

**Status:** approved
**Approved-by:** IchenDEV (user)
**Approved-date:** 2026-09-03
**Upstream:** Failed Release run for tag v0.0.44
  (https://github.com/IchenDEV/utter/actions/runs/33366312954)

## Problem

Tag `v0.0.44` created a GitHub Release page with changelog text but no DMG.
Release Candidate Tests passed. `Sign, Verify & Publish` failed in
**Import signing certificate** while extracting the leaf cert from the
configured `.p12` with OpenSSL 3:

```text
Algorithm (RC2-40-CBC : 0) ... unsupported
```

`security import` of the PKCS#12 into the temporary keychain succeeded; the
subsequent `openssl pkcs12 -clcerts -nokeys` step did not, so build, notarize,
and publish never ran. `v0.0.44` assets remain empty.

## Outcome

A following SemVer tag (proposed `v0.0.45`) completes Sign → Verify → Publish
and attaches a checksummed DMG to the GitHub Release. Certificate import works
on the current macos-26 / OpenSSL 3 runner for the existing
`APPLE_CERTIFICATE_P12` secret without requiring a secret rotate unless the
chosen design explicitly needs one.

## Scope

- Affected: GitHub Actions Release workflow signing-cert import; production
  release tagging path.
- In scope: make PKCS#12 leaf-cert extraction compatible with OpenSSL 3 when
  the bag uses legacy RC2-40-CBC; ship a new release after the fix is on `main`.
- Non-goals: changing codesign identity, notarization credentials, app product
  behavior, or rewriting the self-signed cert generator unless needed for the
  same runner failure mode.

## Constraints

- High-risk lane: signing / release / production publish.
- Do not fall back to ad-hoc signing when configured signing fails.
- Prefer keeping the existing GitHub secret; rotate only if import still fails
  after a runner-compatible extraction path.
- `v0.0.44` already exists as a published release without assets; do not
  overwrite its assets. Ship `v0.0.45` (or next free SemVer) instead.

## Acceptance criteria

- Release workflow import step completes on macos-26 with the current
  `APPLE_CERTIFICATE_P12` secret (or a documented replacement secret).
- Tagging a new SemVer on `main` produces a published GitHub Release that
  includes `Utter-<version>.dmg` and matching `.sha256`, and passes
  `scripts/verify-release-artifact.sh` for the configured signing mode.
- Modern (non-RC2) PKCS#12 inputs still import if supported by the chosen
  extraction path (no regression for freshly exported certs).

## Open questions

- Prefer `openssl pkcs12 ... -legacy` with fallback, or extract the leaf PEM
  from the keychain after `security import` and avoid `openssl pkcs12` for
  fingerprinting?
- Confirm next tag is `v0.0.45`.
