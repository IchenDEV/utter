# Run11 named-rule and installed manifest context

Status: pending approval

The original outer policies differ only in `allow file-write*` subpath predicates. A finite census shows both policies can reapply themselves, and a comment-only variant also succeeds. Applying a different policy fails, including an inner policy with all write grants removed. The missing-write-permission hypothesis is therefore rejected for the measured nested probes. This is bounded context evidence, not full kernel implementation proof or a safe permission fix.

Real Apple Swift 6.2.3 dump-package compiled and linked the package manifest, then failed at sandbox_apply. Its first failure log remains unchanged. One supported very-verbose instrumentation attempt, with the same restrictive outer and the installed inner sandbox enabled, captured the actual inner profile/argv and JSON context. The actual inner grants only ManifestLoading and module-cache writes. It still failed. Safe SwiftPM invocation environment variables were measured; direct manifest child environment was not observed.

Current canaries allowed one task-owned cache write and denied one task-owned write, a loopback connection, and POSIX shared-memory creation with EPERM. Those operations alone are proved. Same-policy nesting is not actual-manifest protection acceptance. No offline resolve was attempted because the real manifest context did not pass.

Fresh HEAD, scoped diff and package/lock hashes match entry. No dependencies were reused, no external scaffold was created, and no product source or original checkout metadata changed. Detailed commands, exact hashes, actual argv/profile, capacity samples and process-group closure are in ignored Run11 artifacts. Native completion remains for owner verification.

Full product build/basic/tests, UI/host/mobile acceptance and Release were not run in this unit. No policy widening, sandbox disabling, permission change, cleanup, network download, recursive delegation or new round occurred. The remaining boundary is different-policy application inside an already sandboxed process while keeping both protection layers. No safe correction is established.
