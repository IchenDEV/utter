# Verification: Add a selectable Espresso ANE inference backend

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/ci-basic-checks.sh` | Pass | Current SDLC, harness, plist, localization, resource, identifier, secret-file, and symlink checks passed |
| `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test` | Pass | 586 XCTest tests passed, 9 skipped, plus 1 Swift Testing test passed after merging the latest settings UI and retaining request-scoped fallback and unload-memory changes |
| Focused fallback and localization tests | Pass | Espresso success avoids MLX; Espresso failure uses MLX; cancellation skips fallback; dual failure preserves both diagnostics; request trackers deallocate and do not cross requests; successful fallback persists MLX; localized status and typed 288 by 56 two-line overlay layout pass |
| `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/build-app.sh --app-only --sign=-` | Pass | Final source without the temporary visual-QA trigger built the Release app and CLI, assembled, ad-hoc signed, and passed artifact verification |
| GitHub run `33296463655`, Xcode 26.6 Release build | Fail; diagnosed | Swift 6.2 emitted cross-module references to three internal `RealModelInferenceEngine.Compiled*` metadata symbols, then failed final arm64 linking |
| Pinned Espresso commit `f3603c7` symbol probe | Pass | The three metadata symbols are emitted as external after changing only the holder types from internal to package visibility |
| GitHub run `33297701825`, Xcode 26.6 | Pass | Contract & Tests, Release-style App Build, and SDLC Gate all passed; the app build completed in 9m12s |
| Independent high-risk reviews | Completed; final passes clean | Successive reviews found stale state, cancellation and selection races, unordered unload/reload, independent integration and benchmark containers, multimodal fallback interleaving, and retained cancelled waiters. The final implementation uses request-scoped outcomes, selection identity checks, one shared processor, and a cancellable reentrant lifecycle gate |
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
- Automatic MLX recovery — pass in focused control-flow tests and a real M5
  Espresso-failure-to-MLX-generation integration test.
- Persisted backend correction — pass with isolated `UserDefaults`; MLX replaces
  Espresso only when Espresso remains the selected backend.
- User feedback — pass in both localizations and real Release windows without
  treating the successful recovery as an error.
- Request and memory lifecycle — pass; outcome trackers deallocate at task end,
  repeated requests remain flat, every production model engine is owned by the
  shared processor, and explicit unload clears MLX active/cache memory after
  active local work completes.
- Existing MLX and remote behavior — pass; complete suite has no failures.
- Direct Espresso generation on a supported host — blocked on the available M5
  Max/macOS 27 host; both the pinned release and upstream main fail in Apple's
  private ANE compiler. The new fallback prevents that failure from blocking
  local formatting when the selected MLX model is installed.

## Residual risk

Espresso still relies on a private ANE interface whose generated programs are
rejected on the available M5 Max/macOS 27 environment. The fallback requires an
already-installed selected MLX model and deliberately does not start a download.
This change makes Utter resilient on M5; it does not establish direct Espresso
or private-ANE compatibility on M5. A public Core ML backend remains separate
future work.

## Decision

Automatic recovery, persistence, regression checks, real M5 fallback, localized
window behavior, dependency resolution, and the Release link are verified.
Direct Espresso inference remains blocked on the tested host. Do not describe
the private ANE backend itself as runtime-compatible with M5 Max/macOS 27.
