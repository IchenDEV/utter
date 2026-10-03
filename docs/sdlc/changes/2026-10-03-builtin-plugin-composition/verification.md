# Verification: Compose Utter from replaceable built-in plugins

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

Implementation is in progress under the approved plan. Partial module tests do
not satisfy whole-product acceptance or authorize release.

## Artifact preparation checks

| Check | Result | Evidence |
| --- | --- | --- |
| `bash scripts/sdlc-checks.sh` | Pass | Approved intent/design/plan and draft verification satisfy the repository artifact gate. |
| Local document links | Pass | Every relative link in the change bundle resolves to an existing file. |
| Document integrity | Pass | All four files have fewer than 300 lines, final newlines, and no trailing whitespace. |
| Baseline macOS contract/tests and release-style build | Pass | [CI run](https://github.com/IchenDEV/utter/actions/runs/36771413938) tested base `9f707331d9a7e29e247a9f47b5b13b23c1236418`; both macos-26 jobs passed. |
| Linux validation access | Available | Official Swift 6.2 Debian toolchain installed temporarily under `/tmp`; Foundation targets compile without SDK substitutions. |

The Linux manifest selects only actual portable targets. It does not build the
macOS app, exercise TCC, or render native windows. Changed macOS targets must pass
the existing project's CI; native behavior evidence is still required.

## Implementation checks

| Check | Result | Scope |
| --- | --- | --- |
| Swift 6.2 portable tests | Pass, 355 tests | Runtime/lifecycle faults, integration/authentication, composition recovery, session settlement, frozen settings/provider choices, targeted history updates, dictionary learning/recovery, resource cancellation/drain, provider registration/replacement, shared structured-value decoding, actual remote transport contracts, cancellation-safe streaming preview resolution, extracted cleaning/fidelity/sanitizer/prompt/fallback regressions, and credential persistence/snapshot contracts. |
| Module boundary fixtures | Pass, 5 tests | Forbidden feature imports and overlapping source ownership are rejected. |
| Actual portable module boundary check | Pass | Runtime, contracts, and extracted lexicon/data sources. |
| Industry vocabulary evaluation | Pass | Real modules: term recall 100%, non-target preservation 100%; unchanged fixture. |
| First extracted macOS build | Pass | [CI run](https://github.com/IchenDEV/utter/actions/runs/37136510317), commit `3535889`: basic checks and assembled app verification passed, including localization bundles and Metal. CI uses an ad-hoc test signature. |
| Extracted macOS tests | Fixture corrected; rerun required | The first run executed 829 tests and the [second run](https://github.com/IchenDEV/utter/actions/runs/37138280093) executed 840 tests, each with 18 skipped and two assertions failing only in the added XPC fixture. Both Objective-C and Foundation expose the original qualified protocol names (`OpenType.OpenTypeXPCProtocol`, `OpenType.OpenTypeXPCEventSink`); the fixture now asserts those observed names. |
| Composition checkpoint macOS build | Pass | The second run assembled and verified the app at `cb9672f`, including localization bundles and Metal. |
| Native settings/session checkpoint tests | Pass | [CI run](https://github.com/IchenDEV/utter/actions/runs/37140908559) at `7702436`: 852 tests, 18 opt-in tests skipped, zero failures. The observed XPC identities and native settings projection contracts passed. An explicit Combine import corrected the preceding checkpoint's compilation failure. |
| Data checkpoint release-style build | Pass | [CI run](https://github.com/IchenDEV/utter/actions/runs/37141571711) at `bac8a5b`: assembled app verification passed. The test job compiled production sources but rejected four extra arguments in the modified deferred-replacement fixture; `2fac5e5` corrected the fixture, with rerun pending. |
| Data and model contracts checkpoint | Pass | [CI run](https://github.com/IchenDEV/utter/actions/runs/37142531271) at `4e00d4d`: 863 tests, 18 opt-in tests skipped, zero failures; release-style app assembly and artifact verification also passed. This rerun includes the corrected deferred-replacement fixture. |
| Apple Speech plugin checkpoint | Pass | [CI run](https://github.com/IchenDEV/utter/actions/runs/37143627313) at `84aa34e`: 866 tests, 18 opt-in tests skipped, zero failures; release-style app assembly passed. Registration preserves permission status and disposal removes its contribution. |
| Remote inference checkpoint | Pass | [CI run](https://github.com/IchenDEV/utter/actions/runs/37144892795) at `d531af9`: 872 tests, 18 opt-in tests skipped, zero failures; release-style app assembly passed. |
| Native backend extraction checkpoint | Compile issue corrected; rerun pending | [CI run](https://github.com/IchenDEV/utter/actions/runs/37145722886) at `401bd00` exposed a missing `HuggingFace` import for the moved `HubCache` parameter. The explicit import is restored; the next checkpoint also compiles extracted native ASR providers and their cancellation/drain contracts. |
| Native ASR extraction checkpoint | Access issue corrected; rerun pending | [CI run](https://github.com/IchenDEV/utter/actions/runs/37146405550) at `f9e66cf` rejected a package-visible property whose streaming-session type is implementation-private. The property now stays within the backend module. |
| Registered processing checkpoint | Witness visibility corrected; rerun pending | [CI run](https://github.com/IchenDEV/utter/actions/runs/37147474621) at `e4d1e69` exposed an internal `LocalizedError` witness on the moved package-level Qwen preprocessing error. Its `errorDescription` now has matching package access. |
| Credential compatibility | Pass, 3 tests | The built-in credentials service delegates to the authoritative preference store, preserves existing keys on reopen, freezes replacement values for a session, and shares token reset/observation with that store. |
| Backend error contracts checkpoint | Name collision corrected | [CI run](https://github.com/IchenDEV/utter/actions/runs/37149694303) at `9a74660` found a `WhisperError` collision with WhisperKit. The provider now explicitly names the contract error. |
| Native backend compilation | Passed backend compilation; caller fixes pending rerun | [CI run](https://github.com/IchenDEV/utter/actions/runs/37150690327) at `8d943c3` compiled the extracted inference providers, then rejected an internal sanitizer type and one missing activity-contract import in application callers. The sanitizer now exports its existing API at package scope. |
| Dictionary corruption faults | Pass, 3 tests | Before the fix, corrupt dictionary/rule files were overwritten (four failed assertions). Both files now retain their original bytes on decode/read failure, while the healthy counterpart persists normally. Storage availability is exposed to presentation. |
| Retry cancellation faults | Pass, 2 tests | Both cancelled and disposed second requests previously escaped as transport errors. A common outer error boundary now normalizes cancellation for the first request and bounded retry, while shutdown awaits drainage. |
| Selected credential projection | Native CI pending | Added tests require reads, edits, token reset, frozen values, publishers, and observer teardown to use the injected credential service without modifying an inactive preference-backed credential source. |
| Native application checkpoint | Build passed; test caller fixes pending rerun | [CI run](https://github.com/IchenDEV/utter/actions/runs/37151492101) at `a0969f0` assembled and verified the app. The test job found old concrete-gate inspection through an existential and missing imports/access for moved audio, gzip, and streaming implementation fixtures. Tests now inject their gate and import the actual owners. |
| Configured fallback ownership | Pass, 8 tests | Six existing regressions now directly test the single portable implementation. New barriers cover cancellation before provider entry and during primary cleanup; the former reproduced an unnecessary primary call before its admission check was added. |
| Download owner shutdown | Pass, 3 tests | The extracted real task ledger drains current and retired non-cooperative writers, rejects publication/admission after closure, and returns a cancelled exclusive waiter without deleting or interrupting the active model. |
| Remote HTTP fault contracts | Pass, 6 tests | Actual client and synthetic transport verify OpenAI/Anthropic request formats, one bounded context-budget retry, non-retry errors, cancellation without retry, and shutdown draining a non-cooperative response. No network or production credentials are used. |
| Session commit fault injection | Regression demonstrated and corrected | Before notification settlement, the five added tests failed with ten assertions: callbacks could observe an incomplete terminal event pair or reenter history commit. The corrected session owner settles state/history/events before notification and checks stream authorization at delivery. |
| Local basic checks | Native step unavailable | Portable module and script fixtures passed. The full script reaches the macOS `PlistBuddy` step, which is unavailable on Linux; the unmodified native checks run in macOS CI. |

Automated native validation uses the existing GitHub macOS CI. The user will
perform real-window, permission-prompt, microphone, and local-model verification
on a macOS 26 Apple Silicon machine after the implementation is ready.

These results cover the current extraction checkpoint. Built-in feature mounting,
effective composition, unified execution, native UI, and full shutdown acceptance
remain incomplete; this is not a completed plugin conversion.
