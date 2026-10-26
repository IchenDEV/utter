# Offline unit Run9

Status: blocked

The bounded protection unit passed. Actual offline dependency registration remains blocked. No resolve or full build ran, and no SwiftPM manifest protection was disabled. The child created no subagents.

## Current binding and capacity

HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`. Parent binary diff `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83` is the entry binding, not an independently recalculated final diff. The child rehashed all 846 parent-listed source files at 2026-10-08T01:31:39.255103+00:00; no file changed. The parent source manifest is `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50`. Package and lock hashes are in the ignored source-after record.

The child entry measured 11374936064 free Data bytes at 01:27:22.813846Z. Every guarded operation persisted its timestamp and byte count before testing the 10737418240-byte floor. Continuous samples accompanied supervised commands. Minimum retained sample was 11344375808 bytes; no floor failure occurred. Fresh external volume UUID and mount point matched before any external canary write. Absolute paths and UUID evidence stay in ignored files.

## Verified protection and failure

The profile reproduces the public SwiftPM default deny policy, imports system.sb, allows file reads and process execution, and grants the two documented Mach services. The manifest canary grants only its two cache directories. A separate outer registration profile grants only the existing task scratch, packagecache, modulecache, clangcache and temp directories. Both profiles explicitly deny network access.

The unsandboxed control could write task files and create task POSIX shared memory. Its loopback TCP attempt returned connection refused, errno 61; this confirms the request reached the network stack, not that a service accepted it. Under each candidate profile, approved cache writes succeeded; task writes outside those approved directories, loopback networking and POSIX shared memory returned EPERM, errno 1. All canary assertions passed. These tests cover those operations, not an exhaustive sandbox audit.

Nested sandbox execution under the narrow manifest profile succeeded at 01:29:49Z. Under the actual registration profile and task cache/TMPDIR environment, the native nested probe exited 71 at 01:31:05Z with `sandbox-exec: sandbox_apply: Operation not permitted`. This establishes a context-specific compatibility failure. It does not establish general OS refusal or a need to increase permissions. The profile and environment differences were not isolated further within the deadline.

The outer registration protection would supplement the original SwiftPM inner manifest sandbox. No --disable-sandbox option was used. Because the exact registration-context nested probe failed, the conditional resolve never started. Actual correction resolve attempts remain zero.

## Installed help and primary evidence

Live xcrun reported Apple Swift 6.2.3, swiftlang-6.2.3.3.21, clang-1700.6.3.2, target arm64-apple-macosx28.0. Installed package and resolve help were retained. Presence of --disable-sandbox in help provides no authorization to remove protection.

Public [SwiftPM Sandbox source](https://raw.githubusercontent.com/swiftlang/swift-package-manager/swift-6.2.3-RELEASE/Sources/Basics/Sandbox.swift) describes the default policy and writable directory rules. [ManifestLoader](https://raw.githubusercontent.com/swiftlang/swift-package-manager/swift-6.2.3-RELEASE/Sources/PackageLoading/ManifestLoader.swift) selects strictness by tools version and grants ManifestLoading/module-cache writes. Exact deployed Apple patch equivalence remains unproven. Retaining its native protection avoids claiming that a replacement profile is equivalent to an unseen Apple patch.

## Retained artifacts and process recovery

Ignored evidence is under `.local/voicecursor-research/run9-offline/`: `child-commands.json`, `child-disk.jsonl`, `child-canary-result.json`, `child-registration.json`, `child-result.json`, both sandbox profiles, both canary programs, command stdout/stderr logs, live catalog/primary evidence, volume evidence and `child-source-after.json`. All 10 supervised command logs match their retained SHA-256 values. They record argv, task environment overrides, start/end, exit and PID/PGID. Initial instruction/setup reads were tool-recorded, but do not have this complete supervisor ledger; no claim of complete initial stdout capture is made.

Every owned supervised process group was reaped. Final process inspection found 0 remaining owned processes. There are no child-owned delegated runs. The owner must record the real T3 native task final state after this turn returns. The child cannot independently certify its own host completed timestamp.

Only two external task cache canary files were written. Prior 19 Git copies and mirror mappings were reused; no original dependency, product source, lock, global config, auth, device, billing, release or owner-exclusive result file changed. The actual workspace registration of all 19 identities/revisions is not proven.

Full build was excluded after its three-minute window closed at 01:28:50Z. SDLC/basic checks, swift test, release-style build, native UI, real host and mobile T0 were not run by this child. Existing approval fields were not changed. Overall execution authorization does not constitute acceptance.

## Minimum remaining requirement

Capture and review the installed SwiftPM manifest sandbox argv and environment in the exact registration context. Isolate why the nested default probe succeeds with the narrow profile but fails with the registration profile and task environment. A supported execution context must retain original inner protection and prove the complete outer boundary before one real offline resolve. Then inspect actual workspace-state for all 19 pinned identities/revisions. No permission, proxy, transport or sandbox bypass is proposed. No new run was created.

Owner feedback 1, 2 and 3 was read. By the final checkpoint there was insufficient supervised time to validate a further conditional path and resolve before 01:31:50Z. The source-bound canary evidence and failed context probe remain reviewable.
