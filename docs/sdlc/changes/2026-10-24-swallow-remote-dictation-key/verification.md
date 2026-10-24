# Verification: Stop the Xiaomi remote's voice key from triggering macOS Dictation

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan](plan.md)

Implementation has not started. Batch 0 (feasibility gate) was executed on 2026-10-25 and is recorded below. The final verification stage (Batch 8) must still be run by an independent verifier after implementation, and must not reuse these spike results as proof of the shipped code.

## Batch 0 — feasibility gate (2026-10-25, spike code only, nothing shipped)

Spike: `/tmp/remaptool` (throwaway, outside the repo). It enumerates HID services through `IOHIDEventSystemClient`, merges `UserKeyMapping` F5 (`0x7_0000_003E`) → `0` while preserving other entries, reads the value back, and polls every 0.5 s for new services. A listen-only event tap counts key events to detect leaks.

| Gate item | Result | Evidence |
|---|---|---|
| Compiles under Swift 6.4, language mode 5 | pass | `swiftc` build clean |
| Needs no permission Utter does not hold | pass | An ad hoc signed app with no Accessibility and no Input Monitoring grant read, set and restored `UserKeyMapping`. No system prompt appeared in any run, confirmed by the user twice |
| Keep the `IOHIDEventSystemClient` alive while using its services | required | Releasing the client early crashed the first probe with `EXC_BAD_ACCESS`. The production provider must own the client for as long as it holds a service |
| Mapping survives a remote disconnect and reconnect | **no, must be re-applied** | Disconnect: service `1000d9eae` disappeared (t = 58 s). Reconnect: new service `1000da8ae` appeared with `hasF5 = false` (t = 60 s) |
| Mapping can be re-applied after reconnect within 30 s | pass | First sighting of the new service and the verified write-back happened in the same poll cycle, so latency is at most one poll interval (about 2 s here), far below the 30 s limit |
| Voice key leaked F5 while the mapping was active | none observed | Over the whole 420 s window, including the stress presses, the remote-only reconnect and the presses right after reconnecting: `f5_down=0 f5_up=0` |
| Other keys still work | pass | `other_key_events=2` (the arrow key down/up). The tap was alive and counting |

Prior control from the spec stage: without the mapping the same real presses produced 17 F5 downs and 2 ups; with it, 0.

### Limits of this evidence

- The first run of this measurement was lost: the watcher was killed when its launching command ended, so that round recorded nothing. The numbers above come from the second, observed run.
- This run has no in-run positive control. It relies on the earlier A/B result and on the tap having counted the arrow key.
- Volume keys are system-defined events and the tap does not count them, so "volume still works" is only inferred from the mapping touching a single usage.
- Sleep/wake persistence was not measured. It is treated like reconnect (the service is recreated, so the mapping is re-applied by the same loop) and must be checked in Batch 8.
- There is a window of up to one poll interval between a new service appearing and the mapping being written. A voice-key press inside that window can still reach macOS. None happened in this run. Batch 3 should prefer a device-matching callback over polling if one is available, and Batch 8 must test a press immediately after reconnect.

### Gate decision

Gate passed: no new permission, and re-application after reconnect is well inside 30 s. The spec's primary design (device-level remap, tap fallback not needed) stands. Awaiting the human decision to proceed to Batch 1.
