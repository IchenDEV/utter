# Utter — Agent Guidelines

## Project Overview

Utter is a macOS menu bar voice input app built with Swift 6 / SwiftUI / AppKit. The Swift package, module, and compatibility identifiers retain the original `OpenType` name. It runs on macOS 26+ (Apple Silicon only) and uses WhisperKit and MLX-LM for local inference, with optional remote LLM support.

## Architecture

- **Pure Swift Package** (no .xcodeproj) — everything is driven by `Package.swift`
- **Composition root**: executable `OpenType` under `Sources/App/`; implementation lives in independently owned SwiftPM targets. `UtterBuiltins` assembles registrations.
- **Functional style preferred** — avoid unnecessary classes; use enums, structs, and free functions where possible
- **File size**: each file should stay under 300 lines (ideally ~100 lines); split when growing

## Module Map

| Directory / target | Responsibility |
|---|---|
| `App/` / `OpenType` | Start and drain `BuiltinApplication`; no processing or UI feature owners |
| `UtterRuntime/` | Plugin graph, scoped services, tasks, revocation and disposal |
| `UtterContracts/` | Portable settings, data, providers, processing evidence and session contracts; localization |
| `UtterMediaContracts/`, `UtterPresentationContracts/` | Native media contracts and observable UI projections |
| `UtterBuiltins/` | Built-in registrations, replacement policy, desktop/recovery compositions |
| `UtterData/` | Settings, credentials, composition persistence, dictionary, lexicons, history and memory |
| `UtterModels/` | Artifact catalog, storage, downloads, frozen model locations and resource access |
| `UtterProcessing/` | Prompt assembly, fidelity checks and replaceable mode recipes |
| `UtterSession/` | Shared session execution, API, follow-up formatting and receipt settlement |
| `UtterIngress/` | Hotkey/remote session bindings and HTTP/XPC transports |
| `UtterAudio/`, `UtterRemoteMic/`, `UtterMacServices/` | Capture, remote device control, OCR, target leases and transactional output |
| `UtterAppleSpeech/`, `UtterWhisper/`, `UtterMLX/`, `UtterANE/`, `UtterRemoteInference/` | Independently registered inference providers |
| `UtterPresentation/` | Menu, onboarding, overlay, icons and settings contributions |
| `UtterEvaluation/` | Headless evaluation schema and finite budgets |

Resources belong to their owner targets; `scripts/resource-bundles.json` is the packaging manifest.
UI and ingress depend on contracts and the runtime; only `UtterBuiltins` imports sibling implementations.
Tests use owner modules directly. Construction fixtures under `Tests/OpenTypeTests/Support/` are excluded from production.

## Key Patterns

- **`@MainActor`** is used for all UI-touching code; background work uses `Task { }` and `actor`
- **Localization**: all user-facing strings go through `L("key")` (defined in `Loc.swift`), with entries in both `en.lproj` and `zh-Hans.lproj`
- **Settings persistence**: `AppSettings` uses `@Published` + Combine `sink` to auto-persist to `UserDefaults`
- **Remote LLM**: `RemoteLLMClient` dispatches to OpenAI-format (`/chat/completions`) or Anthropic-format (`/messages`) based on `provider.apiFormat`
- **Prompt management**: `Sources/UtterProcessing/PromptBuilder.swift` assembles prompts; fixed prompt text belongs in `PromptCatalog.swift` and style presets belong in `PromptStylePrompts.swift`
- **Text processing**: no hardcoded filler-word removal — the LLM handles all contextual cleanup via the system prompt

## Build & Release

- **Dev build**: `swift build`, `bash scripts/build-and-run.sh --verify`, or open `Package.swift` in Xcode
- **Release build**: `bash scripts/build-app.sh` — uses `xcodebuild` (required for Metal shader bundling), then assembles .app and .dmg
- **PR CI**: `.github/workflows/pr.yml` — validates SDLC artifacts, runs linked checks and unit tests, builds a release-style app, and exposes the stable `SDLC Gate` check
- **Release CI**: `.github/workflows/release.yml` — accepts a SemVer tag on `main`, verifies either the existing self-signed identity or Developer ID, requires Apple notarization for Developer ID, and publishes the mounted-DMG-verified artifact with a checksum
- **Icon**: `scripts/generate-icon.swift` programmatically renders the icon and generates `.icns`; `Sources/UtterPresentation/App/AppIcon.swift` renders the same icon at runtime for the Dock

## SDLC Operating Contract

- Read `docs/sdlc/README.md` before non-trivial implementation, automation, test, UI, dependency, permission, or release changes.
- Create or update `docs/sdlc/changes/<yyyy-mm-dd-slug>/`. Low risk requires intent, plan, and verification; medium/high risk also requires a spec.
- **Every stage requires explicit human approval before the next one starts.** Set the artifact's `Status: pending approval` and stop for the user's decision; never mark a stage `approved` on the user's behalf. `approved` requires `Approved-by` and `Approved-date`. Artifacts without a Status header are legacy merged bundles.
- Begin implementation only after intent has observable acceptance criteria and medium/high-risk design choices have been reviewed.
- Always run `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and `swift test`. Add release-style build, real-window visual QA, permission/privacy paths, or clean-machine checks in proportion to risk.
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
