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
| Swift 6.2 portable tests | Pass, 266 tests | Runtime/lifecycle faults, integration/authentication, composition recovery, session settlement, frozen settings/provider choices, targeted history updates, dictionary learning, resource cancellation/drain, provider registration/replacement, shared structured-value decoding, actual remote transport contracts, and cancellation-safe streaming preview resolution. |
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
| Remote HTTP fault contracts | Pass, 6 tests | Actual client and synthetic transport verify OpenAI/Anthropic request formats, one bounded context-budget retry, non-retry errors, cancellation without retry, and shutdown draining a non-cooperative response. No network or production credentials are used. |
| Session commit fault injection | Regression demonstrated and corrected | Before notification settlement, the five added tests failed with ten assertions: callbacks could observe an incomplete terminal event pair or reenter history commit. The corrected session owner settles state/history/events before notification and checks stream authorization at delivery. |
| Local basic checks | Native step unavailable | Portable module and script fixtures passed. The full script reaches the macOS `PlistBuddy` step, which is unavailable on Linux; the unmodified native checks run in macOS CI. |

Automated native validation uses the existing GitHub macOS CI. The user will
perform real-window, permission-prompt, microphone, and local-model verification
on a macOS 26 Apple Silicon machine after the implementation is ready.

These results cover the current extraction checkpoint. Built-in feature mounting,
effective composition, unified execution, native UI, and full shutdown acceptance
remain incomplete; this is not a completed plugin conversion.
