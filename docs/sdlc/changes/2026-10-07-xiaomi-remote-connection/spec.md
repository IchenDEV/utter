# Spec: Xiaomi Remote 2 Pro connection and settings page

**Status:** approved
**Approved-by:** User (conversation: "完成调研后开始实现，无需审批")
**Approved-date:** 2026-10-07
**Upstream:** `intent.md` (approved 2026-10-07)

## Context

`XiaomiRemoteMicBridge.beginScan()` called `scanForPeripherals(withServices:
[ATVV])` and connected the first result. `AudioCaptureManager.start` only uses
the remote when `remoteMicSource.currentSessionToken` is set, which only
happens after an ATVV `AUDIO_START`. The reference implementation
(`remote-mic-app`) instead: retrieves connected peripherals first, scans with no
service filter, accepts a peripheral by advertised service or exact name, reads
Device Information model `2A24`, and decodes `ARN9` low-nibble-first.

## Design

1. `RemoteMicDeviceMatcher` (new, pure): approved-name set, `isCandidate`,
   `usesLowNibbleFirst(modelNumber:)`, and the HID / Device Information UUIDs.
2. Transport seam: `XiaomiRemoteMicCentralTransport.connectedPeripherals(
   withServices:)` returning `RemoteMicKnownPeripheral` values, with a default
   empty implementation so existing fakes are unaffected. The CoreBluetooth
   transport maps `retrieveConnectedPeripherals`.
3. `beginScan()`: after the lifecycle becomes `.scanning`, look up connected
   peripherals for the ATVV service, then the HID service filtered by approved
   name. The first match is routed through the same `routeCentralDidDiscover`
   gate as an advertisement (unbound `sourceAttempt`, same state/lifecycle
   guards), so no new lifecycle path exists. If none, scan with no service
   filter; the delegate proxy drops non-candidates before routing.
4. Model read: connect discovers ATVV plus Device Information; after ATVV
   characteristics, `2A24` is read. `handleModelNumber` is gated by
   `handshake.accepts(attempt)` and sets `decoder.lowNibbleFirst`. `beginScan`
   resets it so a different remote never inherits the order.
5. `RemoteMicDiagnostics` (`@Published` on the bridge): discovery source, model,
   nibble order, and last capture source. `AudioCaptureManager.start` records
   `.remote`, `.systemNoRemoteSession`, or `.systemRemoteUnavailable` when the
   feature is on. `beginScan` keeps the last capture while clearing the rest.
6. `reconnectNow()` is `deactivate()` + `activate()`, reusing the existing
   quiescing gate that defers the new manager until the old one retires.
7. `RemoteMicSettingsView` is a new tab (toggle, connection, audio). Text
   mapping lives in `RemoteMicSettingsText` so it is unit-testable. The controls
   are removed from `GeneralSettingsView`; `AppDelegate` already applies the
   enabled setting, so the duplicate `onChange` is dropped.

## Failure analysis

- Retrieved peripheral is stale or lacks the service: the existing attempt
  fails with `service_missing`, backs off, and retries with a fresh manager.
- Late model read after a reconnect: rejected by the handshake attempt gate.
- Name collision with another ATVV remote: exact names only; advertising the
  ATVV service was already accepted before this change.
- Unfiltered scan noise: filtered in the proxy before any bridge state changes.

## Rollback

Revert the change. The setting key and stored values are unchanged, so no
migration is needed.
