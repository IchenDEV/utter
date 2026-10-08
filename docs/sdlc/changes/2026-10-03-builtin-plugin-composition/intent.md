# Intent: Compose Utter from replaceable built-in plugins

**Status:** approved
**Approved-by:** User (conversation: “批准”)
**Approved-date:** 2026-10-03
**Upstream:** User request, 2026-10-03: adopt DeepSeek Harness-style modularity; confirmed scope is all built-in features with configurable composition.
**Risk:** high — shared input execution, permission-sensitive effects, persisted settings, and public integration compatibility.

## Problem

Utter groups source files by responsibility, but its application features share
one executable target and depend on concrete implementations and global stores.
Adding or replacing a capability still requires changes across application
startup, settings, model routing, and presentation.

The existing implementation and its history expose these structural seams:

| Seam | Evidence | Consequence |
| --- | --- | --- |
| Application composition | [Package.swift](../../../../Package.swift), [AppDelegate](../../../../Sources/App/OpenTypeApp.swift), [integration composition](../../../../Sources/App/AppDelegate+Integrations.swift) | The executable owns both startup and concrete product services; source directories do not enforce module boundaries. |
| Parallel execution coordinators | [VoicePipeline](../../../../Sources/App/VoicePipeline.swift), [InputSessionCoordinator](../../../../Sources/Integration/InputSessionCoordinator.swift) | Menu-bar and integration entries share ownership, speech selection, and text processing, but still implement recording, cancellation, context capture, and output sequencing separately. |
| Closed provider selection | [SpeechEngineProvider](../../../../Sources/Speech/SpeechEngineProvider.swift), [text generation](../../../../Sources/Processing/TextProcessor+Generation.swift), [settings types](../../../../Sources/Config/AppSettingTypes.swift) | Provider availability and construction are coupled to central switches and model/settings knowledge. |
| Global state dependencies | [AppSettings](../../../../Sources/Config/AppSettings.swift), [TextProcessor](../../../../Sources/Processing/TextProcessor.swift), [AppState](../../../../Sources/App/AppState.swift) | Consumers can read live global state or concrete stores instead of an explicitly admitted session configuration. |
| Resource identity | [AppResources](../../../../Sources/Config/AppResources.swift) | Resource lookup assumes the current executable target's generated bundle name, which needs an explicit owner when targets are separated. |

The recent shared-session fix (`7139f54`, PR #113), remote-microphone lifecycle
fixes (`f978e7d`, `e12f699`, `05a8c5a`), local-model lifecycle fix (`d0e6629`),
and [silent-input correction](../2026-09-23-silent-input-insertion/spec.md)
establish behavior that must survive this change. They provide evidence for
shared ownership and commit boundaries rather than a reason to rewrite working
recognizers, storage, or macOS UI.

Not every alternative path is obsolete. The Apple Speech adapter actively uses
the legacy recognizer for streaming and fallback; ANE-LM-to-MLX fallback is also
intentional. Such alternatives must remain explicit behavior inside their owning
capability until evidence supports replacing them.

## Outcome

Utter's existing features are independently replaceable built-in plugins, composed
through validated configuration. The application carrier loads a composition;
product behavior, including session orchestration, is contributed by plugins.
Consumers depend on typed capability contracts rather than concrete providers.

The reference is [DeepSeek Harness architecture](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/architecture.md)
and its [Cordis primer](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/cordis-primer.md):
shared services, typed events, declared dependencies, reversible registrations,
and compositions assembled from bundles and profiles. Utter should apply those
principles to Swift and macOS; the request does not require adopting the Node
runtime, Cordis package, or executable configuration expressions.

## Scope

- Plugin composition and lifecycle: identity, typed capabilities, dependencies,
  activation, deactivation, and observable configuration errors.
- Input entries and sources: menu-bar controls, keyboard shortcuts, local audio,
  remote microphone, imported audio, and existing CLI/HTTP/XPC integrations.
- Speech recognition, streaming, model catalog/download/storage, local MLX and
  ANE-LM inference, remote inference, and multimodal inference.
- Session admission, cancellation, transcript validation, dictation, formatting,
  translation, voice editing, prompt construction, and output delivery.
- Screen and selected-text context, personal/industry dictionaries, correction
  learning, memory, input history, settings, and permission-sensitive services.
- Native presentation: menu bar, overlay, settings, onboarding, history, model
  management, application appearance, localization, and sounds.
- Build and packaging updates necessary to enforce module boundaries and ship
  plugin-owned resources in the existing signed application.

Only built-in plugins are in scope. Third-party installation, dynamic code
loading, a plugin marketplace, arbitrary scripts, and code hot reload are outside
this request. Configuration composition does not imply swapping executing
providers during an active utterance.

## Constraints

- Keep Swift Package Manager, macOS 26+, Apple Silicon, the existing executable
  products, bundle identity, public integration contracts, and persisted user data.
- Keep one authoritative owner for admitted sessions, provider availability,
  settings persistence, and each stored dataset. UI state is a projection of
  execution state; it must not become a second execution authority.
- Preserve immutable per-session choices, exclusive ownership until cancelled
  work drains, authorization before resource changes, and terminal commit rules.
- Preserve speech evidence, prompt-echo rejection, scoped dictionary learning,
  semantic fidelity, focus/replacement guards, and configured fallback behavior.
- A plugin declaration is not a security sandbox. Microphone, screen, selected
  text, credentials, clipboard, and accessibility effects retain their explicit
  permission and privacy boundaries; composition must not silently enable them.
- Prefer existing protocols, pure policy functions, value snapshots, Swift
  standard-library facilities, and native lifecycle mechanisms. Preserve readable
  code and the repository's file-size and localization conventions.
- Compare continued patching, module replacement, and whole-program rewrite
  against implementation, verification, migration, operation, and maintenance
  cost during design. Existing contracts and tests favor bounded replacement;
  whole-program rewriting needs evidence beyond a lower code-generation cost.
- Consolidate each migrated behavior and remove its superseded production path;
  adapters may preserve external compatibility without creating a second runtime.
- High-risk implementation requires independent verification, explicit rollback,
  and the repository's human stage, PR, and production gates.

## Acceptance criteria

1. Every in-scope feature has an owning plugin and declared contracts. Build
   dependencies enforce those boundaries; the composition runtime does not
   depend on concrete recognizers, inference libraries, or native feature views.
2. A test plugin can replace an existing speech or text-generation capability
   through composition without editing application startup or a central provider
   switch. Production plugins use the same registration and dependency mechanism.
3. Configuration can enable, disable, configure, and select built-in plugins.
   Composition is deterministic; duplicate identities/providers, missing required
   dependencies, incompatible configuration, and dependency cycles produce
   actionable errors without partially activating a broken required chain.
4. Failed activation and repeated activation/deactivation leave no duplicate
   event handlers, hotkeys, windows, servers, capture sessions, tasks, or model
   reservations. Shutdown has a defined order and failures remain observable.
5. Menu-bar, remote-microphone, imported-audio, HTTP, and XPC entries use one
   session execution contract. Tests prove exclusivity, frozen settings, stale
   callback rejection, cancellation drain, and no post-cancellation commit.
6. Output effects have an explicit commit boundary: no-speech, invalid transcript,
   unauthorized, failed, or cancelled requests cannot publish final output,
   insert text, write the clipboard, execute an edit, or add success history.
   Existing instant insertion and deferred replacement keep their guarded
   provisional and replacement semantics; successful history commits occur once.
7. Existing recognition modes, formatting, translation, commands, dictionary
   scope, remote authentication, model fallback, and permission timing retain
   their tested behavior. Contract tests and failure injection cover the affected
   seams before their implementations are replaced.
8. Existing settings, credentials, dictionaries, memory, history, model files,
   API payloads/events, and CLI commands remain usable after upgrade. Persisted
   changes, if needed, are versioned, recoverable, and covered by rollback checks.
9. The shipped composition reproduces the existing native app, including English
   and Simplified Chinese resources. Release-style signed packaging and actual
   macOS window checks verify resources, permissions, interaction, light/dark
   appearances, and relevant window sizes.
10. Repository checks and the applicable test suite pass; an independent verifier
    checks risk-critical behavior, superseded execution paths are removed, and
    the eventual PR has no merge conflicts.

## Open questions

- None about the reference or distribution scope: the user confirmed DeepSeek
  Harness and configurable built-in plugins.
- Design review must decide module granularity, service/event contracts, the
  configuration format and precedence, and safe activation boundaries. These
  choices are not approved by this intent.
