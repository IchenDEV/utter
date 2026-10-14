# Run7 SwiftPM offline registration result

Status: pending approval
Date: 2026-10-08

The actual offline dependency registration failed before registering dependency checkouts. All 19 mirrors were configured through the installed SwiftPM CLI. This configuration result does not establish dependency registration or a complete build.

The installed tool is Apple Swift 6.2.3, swiftlang-6.2.3.3.21 and clang-1700.6.3.2. Actual `swift package --help`, mirror help, resolve help, build help and verbose compiler output are retained. The existing external APFS volume identity matched the supplied mapping. Hardware output is retained for owner readback.

## Execution and failure

One initial mirror configuration command failed because the selected task configuration directory did not contain Package.swift. The same run corrected the package context, retained the failed attempt, and successfully configured all 19 URL mappings through `swift package config set-mirror`. The installed CLI actually wrote the task-owned mirror override file. No workspace-state.json was fabricated.

One real `swift package resolve` ran with an outer deny-network sandbox, file-only Git protocol, isolated cache/config/security/scratch paths, disabled credential lookup, skipped updates, disabled prefetching and disabled experimental prebuilts, with forced resolved versions. SwiftPM compiled and linked the real candidate Package.swift manifest. It then failed when its manifest execution attempted a nested sandbox:

`sandbox-exec: sandbox_apply: Operation not permitted`

The process exited 1. This is an execution configuration blocker, not a product-source compiler error. No sandbox or permission settings were changed to bypass it. The command and complete unredacted diagnostic are in ignored task logs.

## Evidence and checks

- Offline SwiftPM dependency registration: failed. No accepted 19-dependency workspace registration.
- Installed mirror CLI and task-owned override: passed, 19 mappings.
- Actual manifest compiler placement: partial. Compiler object, linker executable and overlay paths in verbose output point to the external task temp directory; 37 generated cache/temp files have hashes and device evidence. Product compile placement remains not-run.
- Full candidate build: not-run. Entry at 23:25:30Z left less than three supervised minutes before the 23:28:15Z command deadline.
- Swift tests: not-run.
- Signed release build, native review UI, focus/privacy, real-host apply/cancel/safeRestore and mobile acceptance: not-run; retained as later acceptance work.
- sdlc: interrupted. command deadline
- Source manifest verification: passed, 846 actual files matched the supplied hashes.
- Source HEAD from current readback: `ed4234b41764be8346ae58cdc63011c8f26a0f1e`.
- Source manifest SHA256: `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50`.
- Source-scope tracked diff SHA256: `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`.
- Continuous Data capacity guard: 128 recorded samples; minimum 10767134720 bytes against 10737418240 bytes. No cleanup, threshold reduction or waiting for recovery.
- Every owned command process group: terminal, no remaining members. Command start/end, PID, PGID, exit code and log hashes are retained. Provider native completion remains parent-verified after this response.
- Account quota: unknown. Existing Standard/default route stayed unchanged; no delegates or new rounds.

## Retained files and next action

Detailed result: `.local/voicecursor-research/run7-offline/child-result.json`.
Commands and SHA256 evidence: `commands.json`, `evidence-hashes.json`, `compiler-output.json`, `disk.jsonl`, `source-before.json`, `source-after.json`, `registration-failure-1.json` and `031-offline-resolve.log` in that same ignored directory. Device mappings, UUIDs and absolute compiler paths remain there.

Resolve nested sandbox restriction within an authorized isolated offline execution configuration, verify all 19 SwiftPM identities/revisions, then reserve at least three supervised minutes for one full build. Preserve generated module cache and logs; do not recreate mirrors or metadata.

The supervisor enforces fresh capacity before each owned command and polls it during execution. Each process owns a dedicated group; termination escalates to SIGKILL and confirms the group is empty. Existing dependency files and prior evidence were reused. Product source, package lock, original dependency Git metadata and global configuration received no intentional writes. The 846-file hash check verifies product/source/lock content preservation in this run; the prior 1426-file dependency metadata acceptance was reused, not re-audited. Parent-owned workflow, verification, run state and handoff result files were not edited.

Closing audit: the report was retained after the child deadline. The supervisor rejected new check commands at the command deadline; no further SwiftPM or permission recovery command ran. Exact closing timestamps and the unmet child deadline are recorded in ignored late-close.json.
