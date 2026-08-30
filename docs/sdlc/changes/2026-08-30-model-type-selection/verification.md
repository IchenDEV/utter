# Verification: Make custom models an explicit recommended-first type

## Evidence

- The focused regression loop initially failed on the old presentation order:
  formatting exposed no Custom case or recommended Qwen state, and speech put
  Qwen after Whisper, Apple, and Doubao. After implementation,
  `swift test --filter ConfigurationTests` passed 34 tests.
- `swift test` passed 565 tests with 8 intentionally skipped integration tests
  and no failures.
- `bash scripts/ci-basic-checks.sh` passed, including SDLC validation,
  localization plist linting and key parity, deterministic vocabulary checks,
  conflict-marker checks, and secret-bearing file checks.
- `bash scripts/build-and-run.sh --verify` built, bundled, signed, launched, and
  detected the final app after the temporary QA launch hook had been removed.
- Real-window inspection covered Chinese and English in light and dark
  appearances. Both selectors stayed within the fixed 760-point window. The
  initial full English `Recommended` label exposed horizontal overflow; the
  final localized type marker is `Rec.` in English and `推荐` in Chinese.
- In the live Chinese light window, selecting Custom removed all Qwen entries
  and displayed only the custom model ID field, Add button, and local import.
- `python3 scripts/sdlc.py validate --worktree` and `git diff --check` passed.

## Acceptance criteria

- Explicit Custom formatting type — verified in code, focused tests, and the
  live window.
- Recommended-first Qwen order in both selectors — verified in focused tests
  and both localized live windows.
- Active custom-model synchronization — verified by assigning the catalog
  entry's optional family directly; family-less entries now map to Custom.
- Chinese/English light/dark real-window inspection — verified without clipped
  labels or content overflow.

## Residual risk

The segmented-control recommendation is deliberately abbreviated to `Rec.` in
English to fit five equal-width native segments. The full `Recommended` text
continues to appear on individual recommended model rows. The repository's
path policy classifies the `AppSettings.swift` order change as high risk, so an
independent verifier, final visual approval, PR approval, and any protected
production action remain external gates.

## Decision

Ready for independent and human review. The implementation evidence is current,
and no setting raw values, model IDs, catalog contents, or inference behavior
changed. No independent or human approval is claimed here.
