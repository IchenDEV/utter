# Verification: Compose Utter from replaceable built-in plugins

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

Implementation is in progress under the approved plan. Partial module tests do
not satisfy whole-product acceptance or authorize release.

## Artifact preparation checks

| Check | Result | Evidence |
| --- | --- | --- |
| `bash scripts/sdlc-checks.sh` | Pass | Approved intent/design/plan and draft verification satisfy the repository artifact gate. |
| Local document links | Pass | Every relative link in the change bundle resolves to an existing file. |
| Document integrity | Pass | All four files have fewer than 300 lines, final newlines, and no trailing whitespace. |
| Baseline macOS contract/tests and release-style build | Pass | [CI run](https://github.com/IchenDEV/utter/actions/runs/36771413938) tested base `9f707331d9a7e29e247a9f47b5b13b23c1236418`; both macos-26 jobs passed. |
| Linux validation access | Available | Official Swift 6.2 Debian toolchain installed temporarily under `/tmp`; Foundation targets compile without SDK substitutions. |

The Linux manifest selects only actual portable targets. It does not build the
macOS app, exercise TCC, or render native windows. Changed macOS targets must pass
the existing project's CI; native behavior evidence is still required.

## Implementation checks

| Check | Result | Scope |
| --- | --- | --- |
| Swift 6.2 portable tests | Pass, 22 tests | Runtime graph/lifecycle faults and the moved, unchanged integration serialization regressions. |
| Module boundary fixtures | Pass, 5 tests | Forbidden feature imports and overlapping source ownership are rejected. |
| Actual portable module boundary check | Pass | Runtime, contracts, and extracted lexicon/data sources. |

These results cover the current extraction checkpoint. Built-in feature mounting,
effective composition, unified execution, native UI, and full shutdown acceptance
remain incomplete; this is not a completed plugin conversion.
