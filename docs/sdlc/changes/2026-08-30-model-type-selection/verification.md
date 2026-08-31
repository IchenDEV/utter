# Verification: Make custom models an explicit recommended-first type

## Evidence

- Focused regression tests verify the six presentation types, recommended Qwen
  state, active Custom synchronization, and preservation of explicit Qwen or
  Custom selection when the backend changes from ANE to MLX.
- `swift test` passed 586 tests with 9 intentionally skipped integration tests,
  plus 1 Swift Testing test, with no failures.
- `bash scripts/ci-basic-checks.sh` passed, including SDLC validation,
  localization plist linting and key parity, deterministic vocabulary checks,
  conflict-marker checks, and secret-bearing file checks.
- `bash scripts/build-app.sh --app-only --sign=-` built, bundled, ad-hoc signed,
  and verified the final app after the temporary QA launch hook had been removed.
- Real-window rendering covered Chinese and English in light and dark
  appearances. The six Qwen, Gemma, Llama, ANE, Remote, and Custom segments all
  stayed within the fixed 760-point window. The localized recommendation marker
  remains `Rec.` in English and `推荐` in Chinese.
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
English to fit six equal-width native segments. The full `Recommended` text
continues to appear on individual recommended model rows. The repository's
path policy classifies the `AppSettings.swift` order change as high risk, so an
independent verifier, final visual approval, PR approval, and any protected
production action remain external gates.

## Decision

Ready for independent and human review. The implementation evidence is current,
and no setting raw values, model IDs, catalog contents, or inference behavior
changed. No independent or human approval is claimed here.
