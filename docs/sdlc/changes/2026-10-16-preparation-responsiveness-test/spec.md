# Spec: Deterministic preparation responsiveness

**Status:** approved
**Approved-by:** IchenDEV, explicit continuous scope authorization
**Approved-date:** 2026-10-16
**Upstream:** [intent](intent.md)

The existing detached closure continues to own real generation preparation.
Two default-nil Sendable callbacks bracket that work. ModelStorage forwards them;
production callers keep the defaults. Tests reuse the existing lock and
semaphore gate, shared with the startup cleanup check.

The MainActor starts preparation, waits for worker entry, and records entry
without exit before releasing the worker. A detached watchdog starts before any
MainActor suspension and releases after five seconds, so a whole-worker
MainActor regression fails an assertion instead of hanging. The test still
checks copied bytes and background candidate cleanup with a tiny fixture.

No credentials, network calls, dependencies, signing policy, or product UI change.
Callbacks are internal instrumentation with no persistent state. No synchronous
copy is introduced. On any error, release the gate and clean the fixture.

Verify the positive case and a temporary whole-worker MainActor mutation, restore
the exact source, then rebuild and freeze the complete refreshed test products.
Use native SwiftPM sandboxing for builds and the existing privacy policy for test
processes. Preserve pins and the 10 GiB internal disk floor. Release-style build,
complete local engine execution, independent review, and exact-head CI remain
required. Revert the scoped commit through a PR to roll back.

The owner approved this concrete design through the continuous scope decision
recorded in intent.md. Production remains a separate protected decision.
