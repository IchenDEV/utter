# Spec: Fix OpenSSL 3 PKCS#12 import so releases can ship

**Status:** approved
**Approved-by:** IchenDEV (user)
**Approved-date:** 2026-09-03
**Upstream:** docs/sdlc/changes/2026-09-03-release-p12-openssl3/intent.md

## Context

`.github/workflows/release.yml` imports `APPLE_CERTIFICATE_P12` into a
temporary keychain with `security import`, then runs:

```bash
openssl pkcs12 -in "$CERT_PATH" -clcerts -nokeys \
  -passin "pass:${APPLE_CERTIFICATE_PASSWORD}" -out "$CERT_PEM"
```

to obtain a leaf PEM for SHA-256 fingerprinting and (for non-Developer-ID)
trust. On the macos-26 runner, Homebrew OpenSSL 3 rejects the secret's
legacy RC2-40-CBC PKCS#12 encryption. Keychain import already succeeded in
the failed `v0.0.44` run; only the OpenSSL extraction failed.

## Design

1. Keep `security import` unchanged.
2. Extract the leaf PEM with a two-step OpenSSL call:
   - First try modern `openssl pkcs12 ...` (no `-legacy`) for freshly
     exported AES-style PKCS#12 files.
   - On failure, retry with `-legacy` so RC2-40-CBC bags work on OpenSSL 3.
3. Leave fingerprint / identity / trust / keychain search-list logic as-is.
4. Do not rotate secrets unless the dual-path import still fails on CI.
5. After the fix is on `main`, tag `v0.0.45`. Do not mutate the empty
   `v0.0.44` release assets.

Non-goals: changing notarization, build-app signing flags, or the local
`scripts/create-signing-cert.sh` export defaults in this change (optional
follow-up: export with modern ciphers to avoid `-legacy` long-term).

## Safety and failure modes

- Signing identity and secret material stay in the existing protected
  `production` environment; no new credentials.
- If both OpenSSL attempts fail, the job exits non-zero before any
  codesign / notarize / publish step (same fail-closed behavior as today).
- No ad-hoc unsigned fallback.
- Publish still refuses to replace an existing tag's release assets.

## Test strategy

- Local: dry-run the dual-path `openssl pkcs12` snippet against a throwaway
  modern PKCS#12 and, if available, a legacy-encrypted fixture; confirm
  `-legacy` is accepted by runner-equivalent OpenSSL 3.
- CI: push fix via PR checks; after merge, push `v0.0.45` and observe
  Sign → Verify → Publish success with DMG + sha256 attached.
- Acceptance: release page for `v0.0.45` has artifacts; `v0.0.44` unchanged.

## Rollout and rollback

1. Merge the workflow fix to `main`.
2. Tag `v0.0.45` on the merge commit; let Release workflow publish.
3. Stop if import still fails; diagnose secret format before retagging.
4. Rollback: revert the workflow commit on `main`; leave any successful
   `v0.0.45` assets in place (immutable). Failed tags get a newer SemVer
   after the next fix—do not force-overwrite published assets.
