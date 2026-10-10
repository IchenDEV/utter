import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge {
    func routeCentralDidFailToConnect(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        peripheral: CBPeripheral?,
        error: Error?,
        sourceAttempt: UInt64?
    ) {
        if currentCentralAttempt(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            sourceAttempt: sourceAttempt,
            allowConnected: false
        ) != nil {
            failAttempt(reason: L("remote_mic.error.connect_failed"))
            scheduleCentralRetirementCompletion(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                attempt: sourceAttempt
            )
            return
        }
        scheduleCentralRetirementCompletion(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            attempt: sourceAttempt
        )
    }

    func routeCentralDidDisconnect(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        peripheral: CBPeripheral?,
        error: Error?,
        sourceAttempt: UInt64?
    ) {
        if currentCentralAttempt(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            sourceAttempt: sourceAttempt,
            allowConnected: true
        ) != nil {
            handleDisconnect()
            scheduleCentralRetirementCompletion(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                attempt: sourceAttempt
            )
            return
        }
        scheduleCentralRetirementCompletion(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            attempt: sourceAttempt
        )
    }

    /// Test-only source injection through the same route used by the central
    /// delegate proxy. The optional CoreBluetooth objects are intentionally
    /// absent; source attribution and lifecycle transitions are not fabricated
    /// by looking at a mutable peripheral state.
    package func routeCentralCallbackForTesting(
        _ callback: XiaomiRemoteMicCentralTestCallback,
        attempt: UInt64,
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject
    ) {
        switch callback {
        case .didConnect:
            routeCentralDidConnect(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                peripheral: nil,
                sourceAttempt: attempt
            )
        case .didFailToConnect:
            routeCentralDidFailToConnect(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                peripheral: nil,
                error: nil,
                sourceAttempt: attempt
            )
        case .didDisconnect:
            routeCentralDidDisconnect(
                managerIdentity: managerIdentity,
                peripheralIdentity: peripheralIdentity,
                peripheral: nil,
                error: nil,
                sourceAttempt: attempt
            )
        }
    }

    /// Source gate for central callbacks. Unlike the previous object-state
    /// check, this requires the callback proxy's attempt and the lifecycle
    /// phase to agree. A direct bridge callback has no source envelope and is
    /// rejected for connection events.
    func currentCentralAttempt(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        sourceAttempt: UInt64?,
        allowConnected: Bool
    ) -> UInt64? {
        guard let transport = centralTransport,
              transport.identity === managerIdentity,
              let activePeripheralIdentity = self.peripheralIdentity,
              activePeripheralIdentity === peripheralIdentity else { return nil }
        guard let sourceAttempt,
              activeConnectionAttempt == sourceAttempt,
              handshake.accepts(sourceAttempt) else { return nil }
        guard let active = centralLifecycle.attempt, active == sourceAttempt else { return nil }
        switch centralLifecycle {
        case .connecting:
            break
        case .connected:
            guard allowConnected else { return nil }
        default:
            return nil
        }
        return sourceAttempt
    }

    func scheduleCentralRetirementCompletion(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        attempt: UInt64?
    ) {
        guard let attempt,
              let pending = pendingCentralRetirement,
              pending.attempt == attempt,
              pending.identity === managerIdentity,
              pending.peripheralKey.map({ $0 == ObjectIdentifier(peripheralIdentity) }) ?? true
        else { return }
        finishCentralRetirement(managerIdentity: managerIdentity, attempt: attempt)
    }
}
