# Verification: Add a selectable Espresso ANE inference backend

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/ci-basic-checks.sh` | Pass | Repository basic checks completed after merging `origin/main` |
| `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test` | Pass | 567 XCTest tests passed, 8 skipped, plus 1 Swift Testing test passed after the dependency pin |
| Targeted `ConfigurationTests` | Pass | 36 tests passed, 0 failures |
| `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/build-app.sh --app-only --sign=-` | Pass | Pinned-fork Release app and CLI built, assembled, ad-hoc signed, and passed release artifact verification |
| GitHub run `33296463655`, Xcode 26.6 Release build | Fail; diagnosed | Swift 6.2 emitted cross-module references to three internal `RealModelInferenceEngine.Compiled*` metadata symbols, then failed final arm64 linking |
| Pinned Espresso commit `f3603c7` symbol probe | Pass | The three metadata symbols are emitted as external after changing only the holder types from internal to package visibility |
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

Implementation, regression checks, dependency resolution, and the Release link
are locally verified. The hosted Xcode 26.6 rerun is pending the branch push.
Real inference acceptance remains blocked on the tested host. Do not describe
the backend as runtime-verified on M5 Max/macOS 27 or merge without explicit
acceptance of this risk.
