# Verification: Use native System Settings form structure

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `python3 scripts/sdlc.py validate --worktree` | Pass | All four change bundles validated after the current bundle advanced to `verified` |
| `bash scripts/ci-basic-checks.sh` | Pass | SDLC harness, plist, localization, vocabulary, resource, secret-file, and symlink checks passed |
| `swift test` | Pass | 564 XCTest cases passed, 8 environment-gated cases skipped, and the Swift Testing model-upgrade case passed |
| `bash scripts/build-and-run.sh --verify` | Pass | The final code compiled, assembled, and signed the local app bundle |
| Real-window visual inspection | Pass | All six tabs were inspected at 760 by 680 in Chinese and English, in both light and dark appearances; grouped surfaces, external titles, scrolling, copy, and contrast remained intact |
| `git diff --check` | Pass | No whitespace errors |

## Acceptance criteria

- Native grouped forms — pass; General, Models, Style, Integrations, and About
  render settings in grouped `Form` and `Section` surfaces.
- Decorative page-header removal — pass; the 96-point header, 72-point
  illustration, page badge, panel, and section-wrapper types were removed.
- Compact native choices — pass; speech engine, language style, and model family
  use segmented pickers while preserving their existing bindings and callbacks.
- Chinese/English light/dark real-window inspection — pass across all six tabs.

## Residual risk

Long model and dictionary lists remain denser than ordinary system preference
rows because they expose real managed data. They remain inside a single native
section surface and scroll correctly. Final visual approval remains a human
review decision.

## Decision

Ready for review. Human approval is recorded separately.
