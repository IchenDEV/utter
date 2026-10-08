# Plan: Compose Utter from replaceable built-in plugins

**Status:** approved
**Approved-by:** User (conversation: “确认”)
**Approved-date:** 2026-10-03
**Upstream:** [spec.md](spec.md)

## Execution contract

Implement the [approved design](spec.md), using Ponytail at `full`. Reuse current
engines, storage formats, platform operations, policies, and views. The runtime
supplies composition/lifecycle, while Session and every other product capability
are built-in plugins. No third-party loader, scripting runtime, or hot swap is
introduced.

The work items below are implementation milestones within this plan, not new
SDLC stages. After plan approval, proceed through them without additional routine
milestone approvals. Verification, PR review, and production remain human gates.
Do not mark a milestone complete until its exit evidence exists. Failed checks
are resolved before dependent migration; missing macOS evidence remains explicit.

Each extraction assigns disjoint source/resource paths in `Package.swift`,
retargets existing tests to the owning module, and compiles the changed target and
its consumers. Contract/fault tests precede replacement of the affected seam.
Temporary adapters delegate to the same service instance, own no duplicate state,
and are removed when the corresponding slice converges. Do not release a graph
with old and new executors both active.

## Work items

### 1. Pin the baseline and establish validation access

- [ ] Record the implementation base (currently `9f707331d9a7e29e247a9f47b5b13b23c1236418`)
  and preserve any unrelated workspace changes.
- [ ] Establish Swift 6.2/macOS 26/Apple Silicon build access through the existing
  project CI or an authorized validation host. The current Linux workspace has
  no Swift; do not use fabricated framework stubs as macOS verification.
- [ ] Run baseline repository checks and existing affected regressions. Record
  pre-existing failures separately from regressions introduced by this change.
- [ ] Pin API JSON/events/errors, XPC selectors and Objective-C runtime protocol
  names, legacy preference IDs, dataset paths/formats, and packaged resource names
  with existing fixtures or sanitized synthetic fixtures.
- [ ] Pin cancellation drain, no-speech rejection, settings snapshots, backend
  fallback, clipboard restoration, and deferred replacement behavior with the
  existing suites listed below; add only missing contract cases.

Exit: reproducible baseline and a route to compile/test each migrated macOS slice.

### 2. Introduce contracts and enforce source ownership

- [ ] Add `UtterRuntime`, `UtterContracts`, `UtterMediaContracts`, and
  `UtterPresentationContracts` with the dependencies specified in the design.
- [ ] Move compatible value models and policy inputs without changing serialized
  keys or raw values. Separate `InputContext` values from AppKit capture behavior.
- [ ] Define typed service/provider/configuration/session/receipt contracts; keep
  native audio/image types in media contracts and views in presentation contracts.
- [ ] Replace concrete benchmark/model-error types crossing a boundary with
  contract values. Use `package` access rather than publishing engine internals.
- [ ] Add a module-boundary check under `scripts/`, with a failing fixture proving
  it rejects a forbidden implementation import or overlapping target ownership.

Exit: contract targets compile independently of inference/UI implementations;
existing tests still exercise the moved code, with no duplicate declarations.

### 3. Build the generic runtime and its failure contracts

- [ ] Implement typed keys, descriptors, declared lookup, deterministic graph
  validation, staged activation, readiness, and graph generations.
- [ ] Implement plugin scopes for idempotent contributions, subscriptions, tasks,
  and async resource disposal; unwind failed activation in reverse dependency
  order and aggregate cleanup errors without skipping remaining disposers.
- [ ] Test duplicate services/IDs, missing required dependencies, cycles,
  undeclared lookup, invalid factory registration, and deterministic ordering.
- [ ] Inject failure after every acquired effect; test repeated boot/stop,
  cancelled activation, throwing cleanup, delayed non-cooperative work, stale
  callbacks, and rejection of ingress before readiness or after shutdown.
- [ ] Prove replacement with test plugins through the production catalog/runtime
  mechanism, rather than a separate test-only service locator.

Exit: runtime tests pass with no concrete engine, feature view, or product store.

### 4. Consolidate data and effective configuration

- [ ] Extract `UtterData` plugins for settings, credentials, dictionaries,
  lexicons, history, memory, configuration, and privacy-aware diagnostics.
- [ ] Inject one store instance per dataset; preserve current file/keychain/
  UserDefaults representations. Memory reads the authoritative history service.
- [ ] Decode/validate versioned JSON; compose ordered defaults, legacy preferences,
  and explicit overrides. Check unknown fields/IDs, row replacement, provider
  bindings, atomic writes, future versions, and corruption without data loss.
- [ ] Make effective settings and pending structure observable from one authority.
  UI mutations update the active layer and compatible legacy fields together.
- [ ] Test frozen per-session choices, language/app-scoped dictionaries, existing
  data reopening, preference round trips, and preservation of user composition
  on recovery. Keep credentials out of configuration and general events.

Exit: one owner per store and configuration value; migrated consumers no longer
read global stores or construct private substitutes.

### 5. Replace closed provider selection and model lifecycle

- [ ] Extract `UtterModels`, `UtterAppleSpeech`, `UtterWhisper`, `UtterMLX`,
  `UtterANE`, and `UtterRemoteInference`, retaining their working engine code.
- [ ] Register speech/text/image provider descriptors and legacy IDs through
  scoped registries; replace central constructor/type switches at their callers.
- [ ] Retain Apple analyzer/legacy streaming behavior, Whisper selection rules,
  bounded Qwen hints/echo retry, and existing remote wire-protocol semantics.
- [ ] Move load/status/download/storage ownership to Model service and backend
  adapters. Reuse existing gates for prepare/generate/benchmark/unload; keep MLX
  cache cleanup in its backend and session-owned engines alive until drain.
- [ ] Test fake provider replacement, unavailable model/permission metadata,
  selection changes across awaits, cancelled waiters, unload races, partial
  downloads, and request-local fallback outcomes.

Exit: providers are selected by registered IDs; each model has one status and
resource owner, and metadata registration causes no permission prompt/model load.

### 6. Scope audio and macOS effects

- [ ] Extract `UtterAudio`, `UtterRemoteMic`, and `UtterMacServices` with capture,
  speech evidence, Bluetooth, hotkeys, screen/selection, output, correction,
  sounds, and launch-at-login plugins.
- [ ] Introduce owned recording handles and typed delivery receipts around the
  existing implementations; preserve buffer ownership and caller-file ownership.
- [ ] Test local/remote/file sources, remote release during preparation, old-source
  disconnects, device/clamshell resolution, missing/unreadable audio, speech
  classifier failure, and cancellation without fallback to another microphone.
- [ ] Retain focus/selection/anchor guards, binary clipboard restoration, secure
  correction exclusions, permission timing, and scoped disposal of platform work.
- [ ] Test commit authorization and receipt cleanup: cancellation before commit,
  cancellation during irreversible delivery, uncertain paste, copy recovery,
  no automatic retry, and teardown waiting before reuse of resources.

Exit: platform side effects belong to scoped services; failure/teardown tests show
no duplicate hotkeys, capture, callbacks, tasks, or post-disposal operations.

### 7. Extract processing strategies and configured fallback

- [ ] Move prompt assembly/catalogs, cleaning, fidelity, edit/translation, and
  direct/processed/command mode logic into `UtterProcessing` plugins.
- [ ] Replace concrete generation dependencies with the selected provider
  contracts. Implement ANE-to-MLX fallback through those contracts, unloading ANE
  before fallback and preserving cancellation and configured fallback disablement.
- [ ] Preserve dictionary snapshots, protected tokens, stable prompt prefixes,
  format contracts, multimodal eligibility, and learned-correction scope.
- [ ] Run existing prompt/output/fidelity/edit/translation regressions and fault
  tests for generation failure, empty output, both backends failing, image fallback,
  and cancellation. Use deterministic protocol fixtures for remote services.

Exit: one processing implementation per mode, with no backend implementation
imports and no unreviewed changes to prompt or recognition quality.

### 8. Converge every entry on the Session plugin

- [ ] Extract `UtterSession` around shared ownership/snapshots and one state/event
  owner. Keep API-created sessions resource-free until execution admission.
- [ ] Route menu-bar/hotkey, remote source, imported audio, HTTP, XPC, and CLI
  transport requests through the same authorization/admission/execution contract.
- [ ] Consolidate prepare/capture/transcribe/validate/process/deliver sequencing.
  Every suspension rechecks lease/generation before further work or publication.
- [ ] Settle history and terminal event sequence before subscriber callbacks;
  bind delivery and replacement receipts to their specific history record IDs.
- [ ] Track deferred formatting independently after valid instant insertion;
  replacement reacquires ownership and checks target, anchor, expiry, and generation.
- [ ] Test overlapping entries, unauthorized cancellation, revoked client,
  cancellation at each barrier, stale completion, snapshot/event subscription
  races, subscriber reentrancy, terminal idempotence, and no-speech/echo effects.
- [ ] Remove execution state/tasks/policies from `VoicePipeline`,
  `InputSessionCoordinator`, and transport-owned stores; retain only necessary
  external-name or presentation adapters delegating to the same service.

Exit: production entry traces have one execution owner; cancelled work stays busy
until drained, and no rejected input can reach delivery or success history.

### 9. Compose native presentation and application entry

- [ ] Extract `UtterPresentation`; reuse views and contribute identified settings
  sections/windows through presentation contracts, with stable ordering.
- [ ] Make `AppState` a projection and bind controls to services/commands. Remove
  concrete engine callbacks, global settings reads, and writable execution phases.
- [ ] Build `UtterBuiltins` factories/bundles and the shipped desktop/recovery
  compositions. Reduce the executable to boot, native hosting, and termination.
- [ ] Display effective/pending configuration and actionable recovery errors in
  both languages. Verify uncertain delivery recovery without exposing debug data.
- [ ] Test installed-feature toggles remaining immediate, structural changes
  taking effect after restart, absent-service controls, and recovery with no audio,
  model loading, servers, hotkeys, or output. CLI remains a transport client.
- [ ] Prototype uncertain UI choices in an actual macOS window before applying
  them broadly; retain existing layouts wherever no behavior change requires one.

Exit: shipped composition provides the whole native product, and recovery cannot
activate a disabled sensitive capability or overwrite the invalid user document.

### 10. Finish resource packaging and remove migration paths

- [ ] Move resources to their owners and inject localization language/bundle
  access; remove the hardcoded `OpenType_OpenType.bundle` runtime assumption.
- [ ] Update existing build/verification/icon/lexicon/check scripts to target
  owned resources and an explicit bundle manifest. Preserve all Metal bundles.
- [ ] Add a packaging regression that fails for a missing localization, sound,
  lexicon, illustration/icon, CLI helper, or inference shader resource.
- [ ] Update module guidance in `AGENTS.md` and relevant build documentation.
- [ ] Remove superseded factories, singleton access, executor branches, and
  migration-only adapters. Keep intentional Apple and configured ANE fallbacks.
- [ ] Audit the final dependency graph and every source/mode path; resolve all
  contract failures before final validation rather than broadening the architecture.

Exit: one live implementation per migrated behavior; repository automation and
packaging match the actual target/resource graph.

### 11. Verify the complete product and prepare human review

- [ ] Run the required checks below against the final diff. Re-run earlier checks
  only when a subsequent relevant change, failure, or unresolved risk warrants it.
- [ ] Capture actual macOS window, audio, permission, upgrade, and recovery evidence
  for the manual matrix. Record skips and environmental limits as evidence gaps.
- [ ] Obtain an independent read-only verification pass over accepted artifacts,
  the actual diff, and risk-critical test/build results; fix actionable findings.
- [ ] Map all ten intent criteria to evidence in `verification.md`, include
  rollback results and residual risk, and submit verification for human approval.
- [ ] After verification approval, prepare the conflict-free PR with required
  checks and thread linking. Protected production/release approval remains separate.

## Verification matrix

| Boundary | Tests / evidence |
| --- | --- |
| New runtime and composition | Graph/configuration tests, effect fault injection, idempotent stop/start, stale generations, production-catalog plugin replacement, module import checks |
| Session/cancellation | `InputSessionOwnershipTests`, `OpenTypeServiceTests`, integration HTTP/output/model/auth tests, shared-entry barrier tests |
| Remote/local capture | Remote-mic pipeline/session/handshake/release suites, audio input/activity/sensitivity/conversion suites, classifier and silent-input tests |
| Output/replacement | `TextInsertionCancellationTests`, `RecentInsertionGuardTests`, `DeferredReplacementPolicyTests`, receipt/record-ID/terminal reentrancy tests |
| Models/inference | Model download/recovery/upgrade tests, `LocalModelAccessTests`, Espresso fallback/outcome suites, remote payload/streaming suites |
| Processing/privacy/data | Prompt/fidelity/structured-output/edit/translation suites, dictionary/lexicon/history/memory tests, correction privacy and snapshot tests |
| Packaging/compatibility | JSON/SSE/XPC/CLI fixtures, owned-resource manifest, Metal/resource failure fixture, existing-data and signed-artifact rollback checks |

Required final commands on the macOS validation host:

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh` (including the new linked boundary/resource checks)
- [ ] `swift test`
- [ ] `bash scripts/build-and-run.sh --verify`
- [ ] `bash scripts/build-app.sh --app-only` with the configured signing identity
- [ ] Existing release-artifact verification using the built version and configured
  signing mode; no ad-hoc fallback after a configured identity fails.
- [ ] `git diff --check` and current-main mergeability before PR review

The existing macOS CI provides unit/build evidence; its explicitly ad-hoc build
does not prove stable TCC identity or real-window/hardware behavior. Opt-in model
tests must actually execute, with installed model paths and their existing
integration flags recorded: Apple Speech, native Qwen, Whisper/Volc streaming,
and ANE where configured. A skipped test does not count as model verification.
Use existing audio/quality samples and isolated synthetic stores; do not export
private production history, audio, dictionary, or credentials as test fixtures.

| Manual scenario | Pass condition |
| --- | --- |
| Windows/localization | Menu bar, overlay, settings, onboarding, history, models, and recovery render/interact in light/dark, both locales, and relevant narrow sizes |
| Source and mode parity | Local microphone, remote key, and imported audio reach the shared service; direct/processed/command/translation/edit and streaming retain applicable behavior |
| Speech quality | Quiet/short English/Chinese speech stays usable; silence/noise/echo produce no output; bounded vocabulary and fidelity behavior match accepted baselines |
| Permissions/privacy | Fresh launch defers Apple Speech permission; denied microphone/AX/screen is recoverable; secure fields block learning; authorized client revocation takes immediate effect |
| Delivery races | Cancellation before commit, focus changes, clipboard ownership changes, uncertain paste, expired/deferred replacement, and newer history records obey receipt/anchor rules |
| Lifecycle/configuration | Disable/re-enable operational features, restart structural changes, quit during prepare/capture/process/delivery, and corrupt/future configuration leave no competing owner |
| Upgrade/rollback | Existing preferences/data/model paths survive upgrade; recovery and previous signed artifact can restore operation without deleting user data |

## Completion and gates

Implementation is complete only when all scoped features have plugin owners,
all entries use the shared Session service, obsolete execution paths are removed,
and every intent criterion has evidence. Do not call contract scaffolding, a
partial plugin catalog, or passing unit tests alone completion of this request.

This plan awaits human approval before any implementation or test-code changes.
After implementation, verification needs approval; PR and protected production
gates cannot be approved by the author or independent verifier.
