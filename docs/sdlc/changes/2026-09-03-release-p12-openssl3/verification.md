# Verification: Fix OpenSSL 3 PKCS#12 import so releases can ship

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** docs/sdlc/changes/2026-09-03-release-p12-openssl3/plan.md

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `openssl pkcs12 -help` shows `-legacy` | Pass | Local OpenSSL 3.6.3 lists `-legacy` |
| Dual-path snippet in `release.yml` | Pass | Modern attempt then `-legacy` fallback |
| `bash scripts/sdlc-checks.sh` | Pending | — |
| `bash scripts/ci-basic-checks.sh` | Pending | — |
| `swift test` | Pending / CI | Workflow-only change; PR CI on macos-26 |
| Release `v0.0.45` assets | Pending | After tag push |

## Acceptance criteria

- Import step compatible with OpenSSL 3 legacy PKCS#12 — pending CI release job
- `v0.0.45` publishes DMG + sha256 — pending tag
- Modern PKCS#12 path still attempted first — pass (workflow source)
- `v0.0.44` left unchanged — pending post-release check

## Residual risk

- If the p12 password or blob is wrong, both OpenSSL attempts fail closed (same as before). Owner: release maintainer.
- Runner OpenSSL without `-legacy` would fail the fallback; macos-26 currently ships OpenSSL 3 with `-legacy`. Owner: release maintainer.

## Decision

Draft — fill after local/CI checks; human approval required before production tag.
