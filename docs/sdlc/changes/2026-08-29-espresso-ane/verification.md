# Verification: Add a selectable Espresso ANE inference backend

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/ci-basic-checks.sh` | Pass | Current SDLC, harness, plist, localization, resource, identifier, secret-file, and symlink checks passed |
| `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test` | Pass | 589 XCTest tests passed, 9 skipped, plus 1 Swift Testing test passed with user-selectable fallback behavior |
| Focused fallback, outcome, and settings tests | Pass | 51 tests passed with 1 hardware integration skip; disabling fallback preserves the Espresso error, never invokes MLX, and persists across `AppSettings` reloads; the last generation operation determines the request outcome, non-Espresso generation clears stale outcomes, and cancellation remains neutral |
| Fallback settings real-window matrix | Pass | The 760 by 680 Release settings view rendered Chinese and English in forced Aqua and Dark Aqua; the six model segments, fallback switch, bundle action, and one-line Chinese or two-line English private-API warning remain visible without clipping |
| Final no-QA-hook Release build | Pass | After removing the temporary screenshot entry and its captures, the app and CLI rebuilt, were ad-hoc signed with hardened runtime, and passed release artifact verification |
| Focused fallback and localization tests | Pass | Espresso success avoids MLX; Espresso failure uses MLX; cancellation skips fallback; dual failure preserves both diagnostics; request trackers deallocate and do not cross requests; successful fallback persists MLX; localized status and typed 288 by 56 two-line overlay layout pass |
| `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/build-app.sh --app-only --sign=-` | Pass | Final source without the temporary visual-QA trigger built the Release app and CLI, assembled, ad-hoc signed, and passed artifact verification |
| GitHub run `33296463655`, Xcode 26.6 Release build | Fail; diagnosed | Swift 6.2 emitted cross-module references to three internal `RealModelInferenceEngine.Compiled*` metadata symbols, then failed final arm64 linking |
| Pinned Espresso commit `f3603c7` symbol probe | Pass | The three metadata symbols are emitted as external after changing only the holder types from internal to package visibility |
| GitHub run `33297701825`, Xcode 26.6 | Pass | Contract & Tests, Release-style App Build, and SDLC Gate all passed; the app build completed in 9m12s |
| GitHub run `33304348927`, Xcode 26.6 unit tests | Fail; diagnosed | The empty lifecycle-gate test called `Memory.clearCache()` before any MLX container existed, which made the test runner initialize MLX without an app-bundled default metallib; cache clearing is now conditional on a loaded MLX LLM, benchmark, or VLM container |
| Independent high-risk reviews | Completed; final code review clean | Successive reviews found stale state, cancellation and selection races, unordered unload/reload, independent integration and benchmark containers, multimodal fallback interleaving, retained cancelled waiters, stale first-operation outcomes, and cancellation misreporting. The final implementation uses latest-operation request-scoped outcomes, neutral cancellation, selection identity checks, one shared processor, and a cancellable reentrant lifecycle gate |
| Espresso 0.9.0 GPT-2 generation | Fail | M5 Max/macOS 27 ANE compiler returned code 10, `verifyBundleAtPath: invalid model`, while compiling layer 0 attention |
| Espresso main `eafb33d` GPT-2 generation | Fail | Latest upstream source produced the same ANE code 10 on the same host |
| M5 ANE compile matrix | Fail as expected | All 24 combinations failed: iOS 18, iOS 19, macOS 26, and macOS 27 MIL targets; LayerNorm and RMSNorm; spatial sizes 64, 128, and 256 |
| Real Espresso-to-MLX fallback | Pass | On the M5 Max/macOS 27 host, a real GPT-2 `.esp` bundle produced ANE code 10, then the installed `mlx-community/Qwen3.5-2B-4bit` model generated non-empty output in the same test and produced the fallback notice |
| Repeated fallback memory loop | Pass after fix | Twenty post-fallback MLX requests grew physical footprint by about 64 KiB. Before `Memory.clearCache()`, explicit unload retained about 1.74 GiB over baseline; after the fix MLX reported about 3 KiB active and zero cache memory, and the guarded footprint check passed. `vmmap` identified most remaining delta as empty malloc regions and first-loaded framework pages rather than active model tensors |
| Production model ownership and unload ordering | Pass | AppDelegate injects one processor into voice and integration workflows; benchmarking runs through the same processor and releases its container; focused tests prove unload waits for active local work, nested multimodal transactions are reentrant, and cancelled waiters never run |
| Latest-main settings merge | Pass | The native segmented model picker now orders Qwen, Gemma, Llama, ANE, Remote, and Custom; focused tests preserve explicit selection across ANE-to-MLX backend changes; Chinese and English light/dark 760-point window renders fit; and the complete suite and Release build pass |
| Real-window fallback notice | Pass | The actual Release app displayed the 288 by 56 non-modal completion overlay without truncation in Chinese light and dark appearances and English dark appearance; the temporary environment-triggered QA entry was removed before the final build |

## Acceptance criteria

- Backend selection and persistence — pass; focused settings test and full suite.
- Bundle selection and malformed-bundle rejection — pass at metadata validation level through `ESPRuntimeBundle.open`.
- Espresso warmup and generation dispatch — pass by code path and build coverage.
- User-controlled MLX recovery — pass; automatic fallback defaults on and still
  passes the real M5 integration test, while the disabled setting neither starts
  MLX nor changes the selected Espresso backend.
- Persisted backend correction — pass with isolated `UserDefaults`; MLX replaces
  Espresso only when Espresso remains the selected backend.
- User feedback — pass in both localizations and real Release windows without
  treating the successful recovery as an error.
- Request and memory lifecycle — pass; outcome trackers deallocate at task end,
  the last local operation determines the request result, cancellation does not
  manufacture an Espresso failure, repeated requests remain flat, every
  production model engine is owned by the shared processor, and explicit unload
  clears MLX active/cache memory after active local work completes.
- Existing MLX and remote behavior — pass; complete suite has no failures.
- Direct Espresso generation on a supported host — blocked on the available M5
  Max/macOS 27 host; both the pinned release and upstream main fail in Apple's
  private ANE compiler. The new fallback prevents that failure from blocking
  local formatting when the selected MLX model is installed.

## Residual risk

Espresso still relies on a private ANE interface whose generated programs are
rejected on the available M5 Max/macOS 27 environment. Upstream documents M1
through M4 as tested, but Utter has not independently verified those devices and
private-API behavior may also change with macOS. The fallback requires an
already-installed selected MLX model and deliberately does not start a download.
This change makes Utter resilient on M5; it does not establish direct Espresso
or private-ANE compatibility on M5. A public Core ML backend remains separate
future work.

## Decision

User-controlled recovery, persistence, regression checks, real M5 fallback,
localized window behavior, dependency resolution, and the Release link are verified.
Direct Espresso inference remains blocked on the tested host. Do not describe
the private ANE backend itself as runtime-compatible with M5 Max/macOS 27.
