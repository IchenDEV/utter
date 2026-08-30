# Verification: Replace the Python SDLC validator with a strict shell gate

**Status:** approved
**Approved-by:** chenli
**Approved-date:** 2026-08-31
**Upstream:** [spec.md](spec.md)

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/sdlc-checks.sh` | Pass | All bundles checked; "SDLC checks passed." |
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." |
| `swift test` | Not run locally | mlx-swift Metal shader compilation fails under the local CommandLineTools SDK (pre-existing environment issue, unrelated to these docs/script changes); the PR CI job runs `swift test` on macos-26 |
| Negative: out-of-order approval | Pass | A bundle whose release stage was approved before earlier stages was rejected by the gate during development of change 0001 |

## Acceptance criteria

- Python SDLC toolchain and `state.json` removed — pass (git diff).
- Shell gate passes and enforces order/approval fields — pass.
- No live `sdlc.py` references in prose/CI — pass (historical bundle evidence retains its original text by design).

## Residual risk

- The py validator's governed-changed-paths requirement is not reimplemented; CI compensates with full checks, tests, and release-style build on every PR. Owner: repository maintainer.

## Decision

Ready for review; merge approved by chenli, 2026-08-31.
