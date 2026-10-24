# Verification: Stop the Xiaomi remote's voice key from triggering macOS Dictation

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan](plan.md)

Batches 0 to 7 are implemented and committed. Batch 8 (independent hardware verification) has **not** been run, so this stage cannot be approved yet. Everything under "Implementer's results" was produced by the implementer and does not replace the independent verifier's run.

## Batch 0 — feasibility gate (2026-10-25, spike code only, nothing shipped)

Spike: a throwaway tool outside the repo. It enumerates HID services through `IOHIDEventSystemClient`, merges `UserKeyMapping` F5 (`0x7_0000_003E`) → `0` while preserving other entries, reads the value back, and polls every 0.5 s for new services. A listen-only event tap counts key events to detect leaks.

| Gate item | Result | Evidence |
|---|---|---|
| Compiles under Swift 6.4, language mode 5 | pass | `swiftc` build clean; production code builds with `swift build` |
| Needs no permission Utter does not hold | pass | An ad hoc signed app with no Accessibility and no Input Monitoring grant read, set and restored `UserKeyMapping`. No system prompt appeared in any run, confirmed by the user twice |
| Keep the `IOHIDEventSystemClient` alive while using its services | required | Releasing the client early crashed the first probe with `EXC_BAD_ACCESS`. The production service wrapper retains its client and the provider wraps enumeration in `withExtendedLifetime` |
| Mapping survives a remote disconnect and reconnect | **no, must be re-applied** | Disconnect: service `1000d9eae` disappeared (t = 58 s). Reconnect: new service `1000da8ae` appeared with `hasF5 = false` (t = 60 s) |
| Mapping can be re-applied after reconnect within 30 s | pass | First sighting of the new service and the verified write-back happened in the same poll cycle, so latency is at most one poll interval, far below 30 s |
| Voice key leaked F5 while the mapping was active | none observed | Over the whole 420 s window, including stress presses, the remote-only reconnect and presses right after reconnecting: `f5_down=0 f5_up=0` |
| Other keys still work | pass | `other_key_events=2` (the arrow key down/up). The tap was alive and counting |

Prior control from the spec stage: without the mapping the same real presses produced 17 F5 downs and 2 ups; with it, 0.

Limits: the first measurement round was lost (the watcher was killed when its launching command ended) and redone with a watcher confirmed alive; there was no in-run positive control; volume keys are system-defined events the tap does not count; sleep/wake persistence was not measured.

Gate decision: passed. The user chose to continue with the device-level remap (2026-10-25).

## Implementer's results (Batches 1 to 7)

| Batch | Commit | What it delivers |
|---|---|---|
| 1 | `2348801` | `RemoteKeyRemapState`, diagnostics fields, pure `RemoteKeyMappingPolicy` |
| 2 | `ace9eab` | `RemoteKeyMappingController`: apply, read-back, bounded retry, one re-apply then `conflict`, restore |
| 3 | `4b95ce9` | `RemoteHIDServiceProvider` (public IOKit `hidsystem` API), `RemoteKeyMappingCodec`, `RemoteKeyServiceCatalog` |
| 4 | `4953914` | Setting `remoteKeyRemapEnabled`, default on, stores nothing until changed |
| 5 | `9e71425` | Plugin wiring: start on ready, follow the setting, restore on revoke and dispose, diagnostics overlay, bridge-ready trigger |
| 6 | `9c3758e` | `RemoteKeyRemapRow` on the Remote page, en and zh-Hans strings, render harness, screenshots |
| 7 | `f7f6488` | README (en, zh), release runbook entry, kill switch and manual clear command |

### Automated checks (2026-10-25)

- New tests: 52 plus one render test that only writes screenshots when `UTTER_RENDER_DIR` is set. Policy 14, controller 16, codec 5, service catalog 6, plugin wiring 7, settings 2, localization text 1, read-only hardware smoke 1.
- Full `swift test`: all 15 test bundles passed; `OpenTypeTests` ran 523 tests, 19 skipped, 0 failures. The real remote's mapping was not changed by the run.
- `bash scripts/ci-basic-checks.sh` passed before each of the seven commits; `bash scripts/sdlc-checks.sh` passed.
- Release-style build: `bash scripts/build-app.sh --app-only` succeeded and its release artifact verification passed (2026-10-25). The app is signed ad hoc with the hardened runtime because this Mac has no usable Developer ID or project identity, so the "no extra permission" claim is measured on that build, not on a Developer ID build. The release workflow's signed artifact needs the same check before publishing.
- Read-only hardware smoke: the real provider found the remote's service `4295862446` (`0x1000da8ae`) and decoded its `UserKeyMapping` 20 times without a crash, and wrote nothing.
- Measured cost that shaped Batch 3: this Mac has 244 HID services. Reading vendor and product for all of them took 18.6 ms per poll against 1.65 ms for registry ids only, so the catalog remembers definite verdicts and only reads properties for services it has not judged.

### Deviations from the approved plan and spec

1. **Service-appearance trigger is a 1 s poll.** The public SDK headers declare client creation, `CopyServices`, and service `CopyProperty`/`SetProperty`, but not a device-matching callback; the callback exists only as an undeclared exported symbol. Using it would depend on a private interface, so the public-API poll was chosen (the spec allowed either).
2. **Two small pure files were added in Batch 3** (`RemoteKeyMappingCodec`, `RemoteKeyServiceCatalog`), outside `Native/`, so the decoding rules and the poll-cost cache are unit-tested.
3. **Plugin wiring tests live in `Tests/OpenTypeTests`**, not `UtterRemoteMicTests`, because the plugin fixtures and fake settings are there. The existing plugin fixture now injects a fake provider so no test can touch a real remote.
4. **`waitingForService` is also reported during bounded retries** after a failed write, and `failed` once the attempts are exhausted. The spec's table says `failed` for a set failure; this keeps `failed` meaning "gave up".
5. **State type name** follows the plan (`RemoteKeyRemapState`), not the spec's draft name `RemoteKeyGuardState`.
6. **No separate verify at the start of each remote voice session.** The 1 s poll already reads the mapping and re-applies once on a foreign overwrite, and the bridge ready transition calls `expectRemote()`, which verifies immediately.
7. **A mapping the codec cannot represent** (extra keys in an entry, non-numeric values) is never rewritten: the provider reports it unreadable and the controller ends in `failed` without writing. This was not in the spec and is stricter than it.

### Visual QA (render harness, not the shipped window)

The real `RemoteMicSettingsView` was rendered into an AppKit window through `NSHostingView` in light and dark, English and Chinese, for each state. The first render showed the long conflict and failed sentences squeezing the status row, so the row now shows a short label with the longer explanation as a caption below. Screenshots in [evidence](evidence/): `active-zh-light`, `active-en-dark`, `waiting-en-light`, `no-remote-zh-dark`, `conflict-en-dark`, `failed-zh-light`, `setting-off-en-light`.

Limits: the window is not key, so toggles draw in the inactive grey style (the knob position still shows on or off); this is not the installed app's window. The independent verifier must look at the real Remote page in the release-style build.

## Batch 8 — independent verification (pending)

To be run by a verifier who is not the implementer, on the release-style build (`bash scripts/build-app.sh`), with the installed Utter quit first so two instances never compete for the remote:

- [ ] Hardware A/B with a probe: setting off shows stray text in 5 presses; setting on shows 0 F5 events in at least 50 presses, including holds of 5 s or more and rapid taps.
- [ ] A voice-key press immediately after a reconnect (the up-to-one-poll window noted in Batch 0) and after sleep/wake.
- [ ] Lifecycle read-backs with `hidutil`: app launch, remote off and on, sleep/wake, setting off, Utter quit; a foreign F5 mapping set first by `hidutil` is preserved and restored.
- [ ] Other keys and devices: arrows, Return, volume from the remote still work; the built-in keyboard's mapping reads back as `(null)`.
- [ ] No permission prompt on the release-style build (ad hoc signed here), and on the release workflow's signed artifact before publishing; the README claim "no extra permission" must hold for both.
- [ ] ATVV session with the remote mic on is unchanged against the pre-change baseline.
- [ ] Real Remote page in both languages and both appearances.
- [ ] Record the verifier's identity and result here.
