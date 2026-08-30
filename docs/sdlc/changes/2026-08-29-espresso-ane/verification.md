# Verification: Add a selectable Espresso ANE inference backend

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/ci-basic-checks.sh` | Pass | Repository basic checks completed after merging `origin/main` |
| `swift test` | Pass | 567 XCTest tests passed, 8 skipped, plus 1 Swift Testing test passed |
| Targeted `ConfigurationTests` | Pass | 36 tests passed, 0 failures |
| `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/build-app.sh --app-only --sign=-` | Pass | Release app and CLI built, assembled, ad-hoc signed, and passed release artifact verification |
| Independent high-risk review | Completed; findings addressed | Review found generic ANE errors, stale preload publication, public path logging, and stale loading status; fixes surface localized guidance, use a preload generation token, clear owned loading state, and keep path-bearing details private |
| Espresso 0.9.0 GPT-2 generation | Fail | M5 Max/macOS 27 ANE compiler returned code 10, `verifyBundleAtPath: invalid model`, while compiling layer 0 attention |
| Espresso main `eafb33d` GPT-2 generation | Fail | Latest upstream source produced the same ANE code 10 on the same host |

## Acceptance criteria

- Backend selection and persistence — pass; focused settings test and full suite.
- Bundle selection and malformed-bundle rejection — pass at metadata validation level through `ESPRuntimeBundle.open`.
- Espresso warmup and generation dispatch — pass by code path and build coverage.
- Existing MLX and remote behavior — pass; complete suite has no failures.
- Real generation on a supported host — blocked on the available M5 Max/macOS 27 host; both the pinned release and upstream main fail in Apple's private ANE compiler.

## Residual risk

Espresso relies on a private ANE interface whose generated programs are rejected
on the available M5 Max/macOS 27 environment. Bundle inspection succeeds, so the
failure is only discovered during ANE kernel compilation. The repository
maintainer owns the decision to wait for upstream compatibility, constrain the
supported hardware/OS matrix, or accept the experimental backend. A real-window
light/dark UI pass has not yet been recorded.

## Decision

Implementation and regression checks are ready for review, but real inference
acceptance is blocked on the tested host. Do not describe the backend as runtime-
verified on M5 Max/macOS 27 or merge without explicit acceptance of this risk.
