import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge {
    func routeCentralManagerDidUpdateState(
        managerIdentity: AnyObject,
        managerState: CBManagerState,
        sourceAttempt: UInt64?
    ) {
        guard let transport = centralTransport,
              transport.identity === managerIdentity else { return }
        switch managerState {
        case .poweredOn:
            // Only the unbound scan manager may begin a scan. A callback from
            // a connection manager never restarts the lifecycle.
            if sourceAttempt == nil { beginScan() }
        case .unauthorized:
            guard sourceAttempt == nil || sourceAttempt == centralLifecycle.attempt else { return }
            cancelTimeout()
            cancelReconnect()
            self.state = .unauthorized
        case .unsupported:
            guard sourceAttempt == nil || sourceAttempt == centralLifecycle.attempt else { return }
            cancelTimeout()
            cancelReconnect()
            self.state = .unsupported
        default:
            guard sourceAttempt == nil || sourceAttempt == centralLifecycle.attempt else { return }
            cancelTimeout()
            self.state = .idle
        }
    }

    func routeCentralDidDiscover(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        peripheral: CBPeripheral?,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber,
        sourceAttempt: UInt64?
    ) {
        guard sourceAttempt == nil,
              isActive,
              let transport = centralTransport,
              transport.identity === managerIdentity,
              self.peripheral == nil,
              self.peripheralIdentity == nil,
              state == .scanning,
              case .scanning(_) = centralLifecycle else { return }
        transport.stopScan()
        state = .connecting
        // Bind this central manager to a fresh lifecycle before issuing the
        // connect. Every later central callback from this manager carries the
        // captured attempt through its proxy.
        generation &+= 1
        let attempt = generation
        centralLifecycle = .connecting(attempt)
        transport.delegateProxy.bind(to: attempt)
        transport.delegateProxy.bindPeripheralIdentity(peripheralIdentity)
        beginPeripheralAttempt(
            attempt,
            peripheral: peripheral,
            peripheralIdentity: peripheralIdentity
        )
        startTimeout(
            seconds: Self.connectionTimeout,
            generation: attempt,
            reason: L("remote_mic.error.connection_timeout"),
            isSatisfied: { [weak self] in
                guard let self else { return true }
                return self.generation != attempt || self.handshake.capabilitiesRequested
            }
        )
        transport.connect(to: peripheralIdentity)
    }

    func routeCentralDidConnect(
        managerIdentity: AnyObject,
        peripheralIdentity: AnyObject,
        peripheral: CBPeripheral?,
        sourceAttempt: UInt64?
    ) {
        guard let attempt = currentCentralAttempt(
            managerIdentity: managerIdentity,
            peripheralIdentity: peripheralIdentity,
            sourceAttempt: sourceAttempt,
            allowConnected: false
        ) else { return }
        centralLifecycle = .connected(attempt)
        startTimeout(
            seconds: Self.initializationTimeout,
            generation: attempt,
            reason: L("remote_mic.error.initialization_timeout"),
            isSatisfied: { [weak self] in self?.handshake.isReady ?? false }
        )
        peripheral?.discoverServices([serviceUUID])
    }
}
