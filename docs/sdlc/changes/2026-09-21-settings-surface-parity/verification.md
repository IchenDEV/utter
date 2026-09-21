# Verification: Settings surface parity with System Settings

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md`

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/ci-basic-checks.sh` | Pass | "Basic CI checks passed." |
| `bash scripts/sdlc-checks.sh` | Pass | "SDLC checks passed." |
| `swift test` (full suite) | Pass | 636 tests, 10 skipped, 0 failures |
| `swift test --filter SettingsSurfaceTests` | Pass | 3 tests, 0 failures |
| Screenshot color sampling | Pass | System Settings content `#FFFFFF` / box `#F7F7F7`; Utter page `#F6F6F6` / card `#FFFFFF` |
| Semantic color probe (this machine) | Pass | light: window `#FFFFFF`, underPage `#F6F6F6`; dark: window `#1E1E1E`, underPage `#282828` |

Test command note: this machine has no downloadable Metal toolchain, so the
Xcode build backend cannot compile `mlx-swift`'s Metal sources; the suite ran
with the Xcode toolchain and `--build-system native`.

## Acceptance criteria

- Page surfaces render `windowBackgroundColor`; boxes render
  `underPageBackgroundColor` — pass (`SettingsSurfaceTests` render assertions).
- Box fill distinct from the page — pass (`testCardSurfaceIsDistinctFromPageSurface`).
- All check scripts and `swift test` pass — pass.

## Residual risk

- No real-window light/dark screenshot of the running app was captured in this
  environment; verification is component-level pixel rendering plus code review.
  Reviewer should confirm the six tabs and onboarding on a machine that can run
  the signed app.
- The raw semantic values differ per macOS version; the change tracks the system
  palette by construction rather than pinning values.

## Decision

Ready for review. Human approval is recorded separately.
