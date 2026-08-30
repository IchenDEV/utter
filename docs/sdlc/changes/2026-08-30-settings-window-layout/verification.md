# Verification: Stabilize the settings window and shared layout

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `python3 scripts/sdlc.py validate --worktree` | Pass | Validated all four change bundles after this bundle advanced to `verified` |
| `bash scripts/ci-basic-checks.sh` | Pass | Package, SDLC harness, plist, localization, brand, resource, vocabulary, secret-file, and symlink checks passed |
| `swift test` | Pass | 564 XCTest cases passed, 8 environment-gated cases skipped, and the Swift Testing model-upgrade case passed |
| Focused settings tests | Pass | Exact 760 by 680 content size and non-resizable style mask passed |
| `bash scripts/build-and-run.sh --verify` | Pass | Final code rebuilt, bundled, and signed locally |
| Real-window visual inspection | Pass | All six tabs inspected at 760 by 680 in Chinese and English, in both light and dark appearances; native grouping, copy, scroll containment, and contrast passed; Accessibility reported the zoom button disabled |
| `git diff --check` | Pass | No whitespace errors |

## Acceptance criteria

- Fixed 760 by 680 non-resizable settings window — pass in unit coverage and
  the real AppKit window; zoom was disabled in every inspected tab.
- Native settings geometry plus a shared 28-point Activity/history content edge
  — pass in the compact real window.
- Decorative page-header removal — pass; the earlier vector illustration pass
  was superseded by the accepted native grouped-form direction.
- Chinese/English light/dark real-window validation — pass across all six tabs,
  including fixed-width English tab labels and scrollable long-form content.

## Residual risk

The six legacy PNG illustration resources remain packaged but are no longer
loaded by settings pages. Resource cleanup is intentionally outside this UI-only
change. Visual acceptance remains a human review decision.

## Decision

Ready for review. Human approval is recorded separately.
