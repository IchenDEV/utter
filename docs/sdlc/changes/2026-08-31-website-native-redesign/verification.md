# Verification: Terminal-native website redesign

**Status:** approved
**Approved-by:** repo owner (chat: reviewed prototype renders via screenshots and approved push & deploy)
**Approved-date:** 2026-08-31
**Upstream:** plan.md

## Evidence

- **Design iteration (prototype).** Four variants built; renders reviewed interactively in the in-app browser. User feedback applied: expanded long page + EN/中文 toggle; immersive nav; terminal-window framing + full-mono typography + blinking cursor; light/dark themes; real AppIconLight/AppIconDark; copy refreshed against source. Nav/footer selector collision (`nav` matched both header and footer) found via screenshot and fixed.
- **Copy fidelity.** Model catalog, RAM/disk figures, engines, features, hotkeys, install flow cross-checked against `ModelCatalog.swift`, `DeviceCapability.swift`, `SpeechEngineProvider.swift`, `QwenASRModel.swift`, `AppSettings.swift`, `Package.swift`, `scripts/build-app.sh`, `.github/workflows/release.yml` (see spec table).
- **Local render.** Screenshot-verified in browser at 1280×720 and 1440×900: light theme, dark theme, sticky-nav states, EN and 中文, plus a 320–960px responsive pass via the stylesheet breakpoints.

## Commands

- `bash scripts/sdlc-checks.sh` — pass (the `scripts/sdlc.py` name in AGENTS.md is stale; this is the real gate)
- `bash scripts/sdlc-checks.sh` — pass
- `bash scripts/ci-basic-checks.sh` — pass
- `swift test` — pass locally with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (all XCTest suites + the Swift Testing suite green). Under the default Command Line Tools toolchain the build cannot compile mlx-swift's Metal files (`metal` binary missing) — a pre-existing local-environment limitation unrelated to this docs-only change; PR CI runs `swift test` on full Xcode runners.
- JSON-LD blocks parse as valid JSON (`SoftwareApplication` 9 features, `FAQPage` 7 questions matching the on-page FAQ, `HowTo` 3 steps) — pass

## Residual risk

- The old audio-driven transcript demo is retired; `docs/assets/demos/` audio files remain on disk but are unreferenced (cleanup deliberately out of scope).
- Baidu/other crawlers that ignore JS will only see the English default copy.
- Deployment is observed post-push; rollback is a single revert (see plan.md).
