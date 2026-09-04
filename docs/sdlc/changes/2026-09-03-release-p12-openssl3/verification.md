# Verification: Fix OpenSSL 3 PKCS#12 import so releases can ship

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** docs/sdlc/changes/2026-09-03-release-p12-openssl3/plan.md

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `openssl pkcs12 -help` shows `-legacy` | Pass | Local OpenSSL 3.6.3 lists `-legacy` |
| Dual-path snippet in `release.yml` | Pass | Modern attempt then `-legacy` fallback |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." |
| PR CI Contract & Tests | Pass | https://github.com/IchenDEV/utter/actions/runs/33720711302/job/100539091545 |
| PR CI Release-style App Build | Pass | https://github.com/IchenDEV/utter/actions/runs/33720711302/job/100539091795 |
| PR CI SDLC Gate | Pass | https://github.com/IchenDEV/utter/actions/runs/33720711302/job/100541624657 |
| Release `v0.0.45` assets | Pending | After tag push post-merge |

## Acceptance criteria

- Import step compatible with OpenSSL 3 legacy PKCS#12 — implemented; confirm on Release job
- `v0.0.45` publishes DMG + sha256 — pending tag after merge
- Modern PKCS#12 path still attempted first — pass (workflow source)
- `v0.0.44` left unchanged — pending post-release check

## Residual risk

- If the p12 password or blob is wrong, both OpenSSL attempts fail closed (same as before). Owner: release maintainer.
- Runner OpenSSL without `-legacy` would fail the fallback; macos-26 currently ships OpenSSL 3 with `-legacy`. Owner: release maintainer.
- Final publish proof depends on the production Release environment secrets remaining valid. Owner: release maintainer.

## Decision

Pending human approval of verification evidence; tag `v0.0.45` only after merge + verification approval.
