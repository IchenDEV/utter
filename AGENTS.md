# Utter — Agent Guidelines

## Project Overview

Utter is a macOS menu bar voice input app built with Swift 6 / SwiftUI / AppKit. The Swift package, module, and compatibility identifiers retain the original `OpenType` name. It runs on macOS 26+ (Apple Silicon only) and uses WhisperKit and MLX-LM for local inference, with optional remote LLM support.

## Architecture

- **Pure Swift Package** (no .xcodeproj) — everything is driven by `Package.swift`
- **Single executable target** named `OpenType` under `Sources/`
- **Functional style preferred** — avoid unnecessary classes; use enums, structs, and free functions where possible
- **File size**: each file should stay under 300 lines (ideally ~100 lines); split when growing

## Module Map

| Directory | Responsibility |
|---|---|
| `App/` | Entry point (`OpenTypeApp`), `AppState` (observable), `VoicePipeline` (coordinator), `AppIcon` |
| `Audio/` | `AudioCaptureManager` (AVAudioEngine), `SoundPlayer` |
| `Config/` | `AppSettings` (UserDefaults-backed), `ModelCatalog`, `RemoteModelConfig`, `Loc` (localization helper), `Log` |
| `Hotkey/` | `HotkeyManager` — CGEvent tap for global keyboard shortcuts |
| `LLM/` | `LLMEngine` (MLX local), `RemoteLLMClient` (OpenAI + Anthropic formats) |
| `Output/` | `TextInserter` — Accessibility API text injection with clipboard fallback |
| `Processing/` | `TextProcessor`, `InputHistory`, `MemoryStore`, `PersonalDictionary` |
| `Prompts/` | `PromptBuilder`, prompt catalogs, style prompt presets |
| `Screen/` | `ScreenOCR` — ScreenCaptureKit + Vision framework |
| `Speech/` | `SpeechEngineProtocol`, `AppleSpeechEngine`, `WhisperEngine`, Volc/Qwen/MiMo local ASR support |
| `UI/` | All SwiftUI views: MenuBar, Settings (tabbed), Onboarding, Overlay HUD, History, Models, About |
| `Resources/` | `en.lproj/` and `zh-Hans.lproj/` Localizable.strings, Sounds/ |

## Key Patterns

- **`@MainActor`** is used for all UI-touching code; background work uses `Task { }` and `actor`
- **Localization**: all user-facing strings go through `L("key")` (defined in `Loc.swift`), with entries in both `en.lproj` and `zh-Hans.lproj`
- **Settings persistence**: `AppSettings` uses `@Published` + Combine `sink` to auto-persist to `UserDefaults`
- **Remote LLM**: `RemoteLLMClient` dispatches to OpenAI-format (`/chat/completions`) or Anthropic-format (`/messages`) based on `provider.apiFormat`
- **Prompt management**: `Sources/Prompts/PromptBuilder.swift` assembles prompts; fixed prompt text belongs in `PromptCatalog.swift` and style presets belong in `PromptStylePrompts.swift`
- **Text processing**: no hardcoded filler-word removal — the LLM handles all contextual cleanup via the system prompt

## Build & Release

- **Dev build**: `swift build`, `bash scripts/build-and-run.sh --verify`, or open `Package.swift` in Xcode
- **Release build**: `bash scripts/build-app.sh` — uses `xcodebuild` (required for Metal shader bundling), then assembles .app and .dmg
- **PR CI**: `.github/workflows/pr.yml` — validates SDLC artifacts, runs linked checks and unit tests, builds a release-style app, and exposes the stable `SDLC Gate` check
- **Release CI**: `.github/workflows/release.yml` — accepts a SemVer tag on `main`, verifies either the existing self-signed identity or Developer ID, requires Apple notarization for Developer ID, and publishes the mounted-DMG-verified artifact with a checksum
- **Icon**: `scripts/generate-icon.swift` programmatically renders the icon and generates `.icns`; `Sources/App/AppIcon.swift` renders the same icon at runtime for the Dock

## SDLC Operating Contract

- Read `docs/sdlc/README.md` before non-trivial implementation, automation, test, UI, dependency, permission, or release changes.
- Create or update `docs/sdlc/changes/<yyyy-mm-dd-slug>/`. Low risk requires intent, plan, and verification; medium/high risk also requires a spec.
- Keep `state.json` honest. An agent may advance work to `verified` with current evidence, but may not record its own work as human approval.
- Begin implementation only after intent has observable acceptance criteria and medium/high-risk design choices have been reviewed.
- Always run `python3 scripts/sdlc.py validate --worktree`, `bash scripts/ci-basic-checks.sh`, and `swift test`. Add release-style build, real-window visual QA, permission/privacy paths, or clean-machine checks in proportion to risk.
- High-risk changes require an independent verifier, explicit rollback, PR approval, and protected production approval.
- A production incident must link a corrective intent and add a regression test, deterministic guardrail, eval case, or explicit reason automation is impossible.
- Never fall back to ad-hoc signing when configured signing fails. A self-signed release must use the configured identity, pass the same artifact/checksum checks, and be labeled as not Apple-notarized.

## Coding Conventions

- Swift 6 with `.swiftLanguageMode(.v5)` for compatibility
- Prefer `enum` namespaces (e.g., `enum PromptBuilder { static func ... }`) over classes for stateless logic
- Mark `@MainActor` explicitly on types that touch UI or AppKit
- Use structured concurrency (`async/await`, `Task`, `actor`) — avoid GCD
- All logging through `Log.info()` / `Log.error()` (defined in `Config/Log.swift`)
- Keep repository automation under `scripts/`; do not create another top-level script directory
- Comments: only non-obvious intent, no narrating code

## Common Pitfalls

- **Metal shaders**: `swift build` does NOT bundle `.metallib` files — always use `xcodebuild` for release builds
- **TCC permissions**: ad-hoc signed builds lose permissions on every rebuild; use a signing certificate for stable development
- **Screen Recording permission**: use `SCShareableContent.current` async check, not `CGPreflightScreenCaptureAccess()` alone
- **Apple Speech**: defer `SFSpeechRecognizer.requestAuthorization` until actually needed, not at app launch
