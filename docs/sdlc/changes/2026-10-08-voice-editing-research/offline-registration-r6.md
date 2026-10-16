# Run6 local Git preparation and offline-registration blocker

**Status:** blocked
**Authorization:** Existing overall authorization covers this bounded preparation. This report does not represent product acceptance.

All 19 exact local Git mirrors and working copies pass revision, Git metadata, clean state, recursive submodule and tracked-source checks. The complete 8254-file manifests match Run5, including symlink contents, totaling 145334442 bytes. SwiftPM offline registration, compiler placement, full build, basic checks, swift test and release-style build are **not-run**. Fresh Data stayed below the fixed 10737418240-byte floor. No SwiftPM or compiler executable was invoked, no recovery wait or disk/build retry occurred.

The new `EXTERNAL_TASK_ROOT` passed fresh UUID, external APFS, mounted and writable checks, collision/symlink rejection and nine directory write/fsync/read/hash/device probes. Absolute paths, device identity and detailed mapping remain only in ignored raw. Task-private mirrors, scratch/checkouts, packagecache, Swift/Clang modulecache, temp, config, security and empty-template directories exist. File probes do not prove compiler placement or a populated SwiftPM cache.

## Actual Git evidence

Installed Git version is 2.50.1 Apple Git-155, with local/mirror/no-hardlinks clone options confirmed from installed help. Commands used `git clone --local --no-hardlinks --dissociate --template=EXTERNAL_TASK_ROOT/empty-template --mirror LOCAL_REPOSITORY TASK_MIRROR`, then local no-checkout cloning and `checkout --detach PIN`. MLX submodules were cloned from the already local source submodule Git objects to task mirrors, checked out at their pins and registered under their actual `.gitmodules` names. Recursive status confirms mlx ce45c52505c8158ea48d2a54e8caae05efd86bfe and mlx-c 0726ca922fc902c4c61ef9c27d94132be418e945. No alternates remain in task clones. Task mirror origins are local source repositories; working-copy and submodule origins point to task-local mirrors.

Every managed Git command had `GIT_ALLOW_PROTOCOL=file`, `GIT_TERMINAL_PROMPT=0`, `GIT_OPTIONAL_LOCKS=0`, `GIT_CONFIG_NOSYSTEM=1`, task-private `GIT_CONFIG_GLOBAL`, external `TMPDIR`, disabled fsmonitor and task-private hooks path. All clone arguments were absolute local repository paths. No fetch, remote submodule update, dependency/model download, global config, HOME or credentials change occurred. This is command/protocol evidence; there was no packet capture and no assertion about unrelated processes' networking. No workspace-state was copied or fabricated; no SwiftPM registration is claimed.

| Identity | Exact revision | Revision/source/Git/clean/submodules |
| --- | --- | --- |
| ane-lm | `033472ec12ea796fc7ea4f8cefd7ed456f69900b` | pass |
| argmax-oss-swift | `25c62997041c134b03ca82731ce2f6fd2cae1eb9` | pass |
| eventsource | `a3a85a85214caf642abaa96ae664e4c772a59f6e` | pass |
| mlx-audio-swift | `d302a5c6080d2bb97bae38c7418f82abb76013b6` | pass |
| mlx-swift | `dc43e62d7055353c7f99fa071a4e71d29dfddc44` | pass |
| mlx-swift-lm | `bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57` | pass |
| swift-argument-parser | `6a52f3251125d74daf04fcbd5e6f08a75d074382` | pass |
| swift-asn1 | `eb50cbd14606a9161cbc5d452f18797c90ef0bab` | pass |
| swift-atomics | `b601256eab081c0f92f059e12818ac1d4f178ff7` | pass |
| swift-collections | `fea17c02d767f46b23070fdfdacc28a03a39232a` | pass |
| swift-crypto | `1b6b2e274e85105bfa155183145a1dcfd63331f1` | pass |
| swift-huggingface | `b721959445b617d0bf03910b2b4aced345fd93bf` | pass |
| swift-jinja | `0b67ecb79139f6addef8699eff3622808aa6c7dc` | pass |
| swift-nio | `57c0a08a331aaea9f5d7a932ad94ef43be942a95` | pass |
| swift-numerics | `0c0290ff6b24942dadb83a929ffaaa1481df04a2` | pass |
| swift-syntax | `9de99a78f099e59caf2b2beec65a4c45d54b2081` | pass |
| swift-system | `7c6ad0fc39d0763e0b699210e4124afd5041c5df` | pass |
| swift-transformers | `2fa33e1f5e7131a7fc64c28e6d161dcec0d24820` | pass |
| yyjson | `8b4a38dc994a110abaec8a400615567bd996105f` | pass |

Original dependency Git metadata was hashed before and after, including bare repositories, checkout Git directories and submodule metadata. 1426 metadata files matched, canonical SHA256 `bf5967b0393dd394c7c0b61a14d316ad47281695e25ce5ee15b7e8a0a02c0185`. The root HEAD remains `ed4234b41764be8346ae58cdc63011c8f26a0f1e`, tracked binary diff SHA256 `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`, and the complete 846-file source/script/resource manifest SHA256 `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50`. Package.swift and Package.resolved are unchanged. Run5 snapshots and evidence remain untouched.

## Data and terminal evidence

- 2026-10-07T22:54:06.465926+00:00: 10287767552 bytes, 9.581230 GiB.
- 2026-10-07T22:54:46.786570+00:00: 10281578496 bytes, 9.575466 GiB.
- 2026-10-07T22:55:18.471362+00:00: 10283343872 bytes, 9.577110 GiB.

Preparation supervisor attempt 1 ran 2026-10-07T22:54:06.398316Z to22:54:18.191360Z, exit1. The actual error was task submodule registration under a directory path rather than its `.gitmodules` name; recursive status correctly reported unregistered submodules. Failure JSON/logs remain preserved. One same-run recovery fixed the mapping and reused only the validated task root, without deleting files. Attempt 2 ran 2026-10-07T22:54:46.716986+00:00 to 2026-10-07T22:55:18.471387+00:00, exit0. All managed command PGIDs were bounded to the unchanged22:56:40Z internal deadline and reaped, with zero remaining processes. The owner's command deadline remains22:56:50Z. Native agent completion must be read by the parent after return; artifact timestamps are not native terminal evidence.

Raw `.local/voicecursor-research/run6-offline/command-records.json` records every actual invocation/environment/start/end/exit/PID/PGID/log SHA256. `dependencies.json`, 19 source manifests, full-source-manifest-after.json, original-git-metadata-before/after.json, metadata-preservation-summary.json, failure JSON, external-mapping.json, process-terminal.json and evidence-hashes.json retain the evidence. No new Swift/help/compiler probe was executed below the floor; Run5 Swift/tool help is historical evidence only, not a fresh tool-version binding or registration result.

Next: fresh Data>=10GiB plus enough supervised time, then real offline SwiftPM registration using these local repositories with isolated config/cache/security/scratch/temp. Verify SwiftPM reads and accepts the exact identities and revisions before a single complete build, with at least three minutes remaining and continuous10GiB PGID protection. Compiler arguments and actual written cache/temp artifacts still need proof. Complete build precedes Cursor native review/focus/privacy and independent real-host checks. Mobile remains the original owner's T0 and device reservation; no manual-return acceptance. No child delegation, UI, host, device, production-workspace, signing, commit, push, PR or release work occurred.

sdlc passed, exit0, 2026-10-07T22:56:16.440173+00:00 to 2026-10-07T22:56:18.068540+00:00, log SHA256 `5ed5fb27bb8a18b455bb5c10b900d0e0b602a1b7dc598eecbd736cacdc07bfc0`.

diff-check passed, exit0, 2026-10-07T22:56:18.069206+00:00 to 2026-10-07T22:56:18.109209+00:00, log SHA256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
