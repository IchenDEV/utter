# Verification: Confucius4-R2T2 MLX speech recognition in Utter

**Status:** approved
**Approved-by:** user (chat: "批准")
**Approved-date:** 2026-09-23
**Upstream:** plan.md

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Pinned Swift MLX runtime | Pass | `mlx-audio-swift` 0.1.3 loaded the actual `mlx-community/Confucius4-R2T2-8bit` repository. English output: `Hey, so um, I wanted to, I wanted to follow up on the design doc we talked about.` Chinese output contained `周五之前能review一下？`. |
| Mid-sentence stop | Pass | A 3.1 s cut of `en-sample.m4a` ended in `I wanted to|` without padding; with 0.5 s of silence it continued to `I wanted to follow` without a trailing marker. The regression clip is `docs/assets/demos/confucius-mid-sentence.wav`. |
| Focused model tests | Pass | `OPENTYPE_CONFUCIUS_MODEL_PATH=/tmp/utter-confucius4-r2t2-8bit swift test --filter ConfuciusASRTests`: 4 tests, 0 failures. A final timed run took 14.19 s including SwiftPM setup; XCTest took 1.83 s. `/usr/bin/time -l` reported 2,682,716,160 bytes maximum resident set size for the command and child test process, not an isolated model-only peak. |
| `bash scripts/sdlc-checks.sh` | Pass | `SDLC checks passed.` |
| `bash scripts/ci-basic-checks.sh` | Pass | `Basic CI checks passed.` Localization and repository invariants passed. |
| `swift test` | Pass | 752 XCTest executed, 15 environment-gated skips, 0 failures; one Swift Testing test passed. The model-weight integration test was run separately above. |
| Release-style app build | Pass | Final `bash scripts/build-app.sh --app-only` passed; `dist/Utter.app` assembled with `default.metallib` and passed artifact verification. This local build used ad-hoc signing and is not a production release. |
| Real-window UI render | Pass | An AppKit `NSWindow` hosted the model-management view at 760 × 680 in light and dark appearances. Reviewed `review-evidence/2026-09-23-confucius4-r2t2-mlx/light.png` and `dark.png`: Confucius4 row, active badge, download action, hint, Chinese license, English license, and conversion notice links are visible without clipping or contrast loss. The native interaction channel failed to start, so button clicks were not observed in the running app. |

## Acceptance criteria

- Model selection and localized labels — pass for catalog contract, localization parity, and rendered selected-model state. English strings were validated by parity checks; the window captures used Chinese UI language.
- Download completion — pass for file contract against the real downloaded repository, including weights and license notices. The new repository's full in-app network download was not rerun; it follows the unchanged staged Hub path.
- Cancellation, retry, deletion, and switching — generic model-management and download-recovery tests passed in the full suite; exact-model UI clicks and a second 2.48 GB network transfer were not performed.
- On-device transcription — pass for English, Chinese, and mid-sentence clips with the pinned runtime and model-specific tail silence.
- Existing engines remain functional — full suite passed; the default Qwen model is not modified by the tail-padding branch.

## Residual risk

- Release owner must review the NetEase model license and in-app download flow before distribution. The repository's Chinese agreement prevails and says the separate-license revenue threshold is RMB 100 million, while its English copy says RMB 1 billion. The app links both licenses and the conversion notice and requires the downloaded `LICENSE`, `MODEL_LICENSE_zh`, and `NOTICE` files; weights are not bundled.
- Native UI interaction and an actual in-app download/cancel/delete session for this exact repository were not observed because the computer-use native pipe failed. The unchanged generic paths have automated coverage, but this remains a release verification gap.

## Decision

The local implementation passed the approved verification stage. Production distribution remains gated on the license decision and an in-app download/selection/deletion check in a working native UI session.
