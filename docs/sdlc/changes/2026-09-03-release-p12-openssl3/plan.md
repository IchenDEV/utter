# Plan: Fix OpenSSL 3 PKCS#12 import so releases can ship

**Status:** approved
**Approved-by:** IchenDEV (user)
**Approved-date:** 2026-09-03
**Upstream:** docs/sdlc/changes/2026-09-03-release-p12-openssl3/spec.md

## Work items

1. Update `.github/workflows/release.yml` **Import signing certificate**:
   try `openssl pkcs12 ... -clcerts -nokeys` without `-legacy`; on
   non-zero exit, retry with `-legacy`; keep fingerprint / identity /
   trust steps unchanged.
2. Add SDLC `verification.md` after checks; keep this change-bundle
   docs in sync through the PR.
3. Open PR to `main`; run `bash scripts/sdlc-checks.sh`,
   `bash scripts/ci-basic-checks.sh`, and `swift test` as required for
   the gate (workflow-only change still needs the repository checks).
4. After merge, create annotated tag `v0.0.45` on `main` and push the
   tag to trigger Release; confirm DMG + sha256 publish.
5. Leave `v0.0.44` untouched.

## Verification plan

| Check | How |
|---|---|
| Dual-path OpenSSL accepts `-legacy` on OpenSSL 3 | Local `openssl pkcs12 -help` / dry extract if a fixture exists |
| SDLC / CI basic / unit tests | `sdlc-checks.sh`, `ci-basic-checks.sh`, `swift test` |
| Real release publish | GitHub Actions Release for `v0.0.45`; assets present |
| No overwrite of `v0.0.44` | `gh release view v0.0.44` still has empty or prior assets unchanged |

## Out of scope this PR

- Regenerating `APPLE_CERTIFICATE_P12`
- Changing `scripts/create-signing-cert.sh` default export cipher
- Product / app code changes
