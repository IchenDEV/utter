# Plan: Stop the Xiaomi remote's voice key from triggering macOS Dictation

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (2026-10-25 00:30 UTC+8; scope: both artifacts listed in the preceding review message)
**Approved-date:** 2026-10-25
**Upstream:** [spec](spec.md) (approved 2026-10-25)

Each batch is one commit, small enough to review alone. Before every commit run `swift build`, the batch's focused `swift test --filter`, and `bash scripts/ci-basic-checks.sh`. Every new file stays under 300 lines. The implementer is one agent; the independent verifier in batch 8 is a different one.

## Work items

### Batch 0: feasibility gate (no production code; go/no-go for spec D1 and D4)

- [ ] Compile check: a scratch Swift file in the worktree calls `IOHIDEventSystemClientCreateSimpleClient`, `IOHIDEventSystemClientCopyServices`, `IOHIDServiceClientCopyProperty`, and `IOHIDServiceClientSetProperty` under the repo's Swift 6 toolchain and macOS 26 SDK, with `.swiftLanguageMode(.v5)`. Delete the file afterwards.
- [ ] Permission measurement (spec D4): run the same calls from a minimal ad hoc signed `.app` launched with `open`, so it carries none of Cursor's or Terminal's permissions, with Accessibility and Input Monitoring absent for it. Record whether the set and the read-back succeed and whether any system prompt appears.
- [ ] Service-appearance measurement: with the remote connected, record whether the mapping survives (a) the remote disconnecting and reconnecting, (b) sleep and wake. Record how long after reconnect the HID service becomes visible, and whether an event-system matching notification exists without extra permission; otherwise measure a 2 s poll.
- [ ] Long-hold and volume check: with the mapping applied via `hidutil`, 50 voice-key presses including holds of at least 5 s and rapid taps give 0 keycode-96 events; volume and arrow keys still arrive.
- **Gate:** if setting needs a permission Utter does not hold, or the mapping cannot be re-applied after reconnect within 30 s, stop and bring the evidence back for a spec revision (tap fallback). Results go into `verification.md`.

### Batch 1: contracts and pure policy

- [ ] `Sources/UtterContracts/RemoteKeyRemapState.swift`: `RemoteKeyRemapState` (`off`, `noRemote`, `waitingForService`, `active`, `conflict`, `failed`) and a re-apply counter type; extend `RemoteMicDiagnostics` with `keyRemap` and `keyRemapReapplyCount`.
- [ ] `Sources/UtterRemoteMic/RemoteKeyMappingPolicy.swift` (pure): vendor/product table (`0x2717`, `0x32B8`), source usage `0x7_0000_003E`, destination `0`; `applying(existing:)` and `restoring(original:current:)` per the spec; exact-entry detection.
- [ ] Tests in `Tests/UtterRemoteMicTests/RemoteKeyMappingPolicyTests.swift`: unrelated entries preserved and order stable; foreign F5 entry replaced and later restored; idempotent apply; our entry detected exactly; empty list.

### Batch 2: controller state machine

- [ ] `Sources/UtterRemoteMic/RemoteKeyMappingController.swift`: injectable service provider and clock; `apply`, `verify`, `restore`; read-back before reporting `active`; partial-failure rollback to the snapshot; bounded retry (about 10 attempts over 30 s); one re-apply on a foreign overwrite, then `conflict`; no unbounded loop.
- [ ] Tests in `Tests/UtterRemoteMicTests/RemoteKeyMappingControllerTests.swift` with a fake provider and clock: success, no service, set failure and rollback, read-back mismatch, retry bounds, reappearing service, conflict, restore after apply, disable while retrying, idempotent calls, never touches unmatched services.

### Batch 3: native provider and service-appearance trigger

- [ ] `Sources/UtterRemoteMic/Native/RemoteHIDServiceProvider.swift`: the thin layer over the event-system client calls from batch 0, filtered by vendor/product, reading and writing only `UserKeyMapping`. The service-appearance trigger uses whichever mechanism batch 0 proved needs no extra permission.
- [ ] No behavior beyond the protocol the controller defines; tests cover the filter logic through a fake service list. The real calls are exercised in batch 8.

### Batch 4: setting `remoteKeyRemapEnabled`

- [ ] `SettingsValues`: `remoteKeyRemapEnabled: Bool = true`. `SettingsStore+Load`: a missing key reads as true, otherwise the stored value. `SettingsStore+Persistence` writes it.
- [ ] Tests in `Tests/UtterDataTests/SettingsStoreTests.swift`: default true on a fresh store, round trip of false and true. This setting is also the runtime kill switch (`defaults write com.opentype.voiceinput remoteKeyRemapEnabled -bool false`).

### Batch 5: lifecycle wiring and diagnostics

- [ ] `RemoteMicPlugins`: create the controller beside the bridge; start it in `onReady`; follow `remoteKeyRemapEnabled` through `settings.observe`; on revoke and dispose call `restore()`. Independent of `remoteMicEnabled`.
- [ ] `RemoteMicController`: merge the remap state into the diagnostics it publishes and notify observers on change; when the remote mic is on, a Bluetooth ready transition triggers a verify.
- [ ] Tests in `Tests/UtterRemoteMicTests`: plugin-level wiring with fakes (apply on ready, restore on revoke, setting toggled off restores, independent of `remoteMicEnabled`), diagnostics merge.

### Batch 6: settings page and strings

- [ ] `Sources/UtterPresentation/UI/RemoteKeyRemapRow.swift`: a toggle bound to `remoteKeyRemapEnabled` plus a status line from `RemoteKeyRemapState`. Place it in its own `Section` in `RemoteMicSettingsView` outside the `if settings.remoteMicEnabled` block, so it shows with the remote mic off; disable it when no remote provider exists, like the mic toggle.
- [ ] `en.lproj` and `zh-Hans.lproj` strings for the title, help, and each state; localization parity check passes.
- [ ] Real-window visual QA: light and dark, en and zh-Hans, state values; screenshots recorded in `verification.md`.

### Batch 7: docs and runbook

- [ ] Troubleshooting entry and the release runbook note: what the setting does, the kill switch, the manual clear command `hidutil property --matching '{"VendorID":10007,"ProductID":12984}' --set '{"UserKeyMapping":[]}'`, and that a reconnect also clears a leftover mapping.
- [ ] Release note line about the Remote page setting.

### Batch 8: verification (independent verifier)

- [ ] Hardware A/B with a probe app: control (setting off) shows stray text in 5 presses; treatment (setting on) shows 0 F5 events in at least 50 presses, including holds of 5 s or more and rapid taps.
- [ ] Lifecycle read-backs: remote off/on, sleep/wake, setting off, Utter quit; each followed by a `hidutil` read-back; a foreign F5 mapping set first by `hidutil` is preserved and restored.
- [ ] Other keys and devices: arrows, Return, and volume from the remote still work; the built-in keyboard mapping reads back as `(null)`.
- [ ] ATVV session with the remote mic on is unchanged against the pre-change baseline log.
- [ ] Record everything in `verification.md`, including the independent verifier's identity and result.

## Verification plan

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] Release-style build (`bash scripts/build-app.sh`) and a run of that build for batch 8, because permission behavior depends on the signed app.
- [ ] Real-window visual QA for the settings row (batch 6).
- [ ] Hardware checks from batch 8, repeated by the independent verifier.

## Human gates

- Batch 0 result: the user decides whether to continue with the device remap or revise the spec toward the tap fallback.
- Each stage artifact (`plan`, then `verification`) needs explicit approval before the next stage starts.
- PR approval, then release approval, for this high-risk change; the release is not cut without the independent verifier's recorded result.
- Any need to request a new permission for the remap is a new decision and returns to the user.
