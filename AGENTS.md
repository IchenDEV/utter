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
- **CI**: `.github/workflows/release.yml` — builds on macOS, signs, optionally notarizes, publishes to GitHub Releases
- **Icon**: `scripts/generate-icon.swift` programmatically renders the icon and generates `.icns`; `Sources/App/AppIcon.swift` renders the same icon at runtime for the Dock

## Coding Conventions

- Swift 6 with `.swiftLanguageMode(.v5)` for compatibility
- Prefer `enum` namespaces (e.g., `enum PromptBuilder { static func ... }`) over classes for stateless logic
- Mark `@MainActor` explicitly on types that touch UI or AppKit
- Use structured concurrency (`async/await`, `Task`, `actor`) — avoid GCD
- All logging through `Log.info()` / `Log.error()` (defined in `Config/Log.swift`)
- Keep repository automation under `scripts/`; do not create another top-level script directory
- Comments: only non-obvious intent, no narrating code

## SDLC (strict per-stage approval)

Every change follows `Intent -> Spec -> Plan -> Build -> Verification -> Release`, tracked as artifacts under `docs/sdlc/changes/<NNNN>-<slug>/` (see `docs/sdlc/README.md`). Rules:

- **Each stage requires explicit human approval before the next stage starts.** Fill in `intent.md` (or the next needed stage), set `Status: pending approval`, and stop for the user's decision. Never mark a stage `approved` on the user's behalf; only record an approval the user actually gave.
- `Status` values: `draft | pending approval | approved | rejected | blocked`; `approved` requires `Approved-by` and `Approved-date`. Rejections and blocks stay in the artifact with a reason.
- Stage order is enforced by `scripts/sdlc-checks.sh`, which runs in PR CI via `scripts/ci-basic-checks.sh`.
- Build only within the plan's authorized scope; verification records real commands and results (failures included). `docs/superpowers/` is a read-only archive of pre-2026-08 specs/plans — do not add new files there.

## Common Pitfalls

- **Metal shaders**: `swift build` does NOT bundle `.metallib` files — always use `xcodebuild` for release builds
- **TCC permissions**: ad-hoc signed builds lose permissions on every rebuild; use a signing certificate for stable development
- **Screen Recording permission**: use `SCShareableContent.current` async check, not `CGPreflightScreenCaptureAccess()` alone
- **Apple Speech**: defer `SFSpeechRecognizer.requestAuthorization` until actually needed, not at app launch
