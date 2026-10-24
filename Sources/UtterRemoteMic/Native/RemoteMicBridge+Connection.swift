import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge {
    // MARK: - Scanning and connection

    func beginScan() {
        guard isActive else { return }
        switch centralLifecycle {
        case .quiescing:
            // A replacement transport is not created until the old transport
            // reports terminal cancellation (or the scan fence completes).
            scanRequestedWhileQuiescing = true
            return
        case .scanning(_), .connecting(_), .connected(_):
            return
        case .idle:
            break
        }
        guard let transport = centralTransport else {
            installCentralTransport()
            return
        }
        guard transport.state == .poweredOn else { return }
        generation &+= 1
        resetPeripheral()
        resetStream()
        handshake.reset()
        capabilities = .default
        centralLifecycle = .scanning(generation)
        state = .scanning
        transport.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Creates the central transport through the same factory used by the
    /// production CoreBluetooth initializer. A transport is never reused after
    /// its connection is retired, because its delegate callbacks otherwise
    /// carry no source id.
    func installCentralTransport() {
        guard centralTransport == nil else { return }
        let transport = centralTransportFactory?()
            ?? XiaomiRemoteMicCoreBluetoothCentralTransport(bridge: self)
        transport.delegateProxy.bindManagerIdentity(transport.identity)
        centralTransport = transport
    }

    /// Retires the current central transport. A pending or connected
    /// peripheral is always passed to `cancel`; CoreBluetooth documents that
    /// this cancels pending as well as active local connections. The old
    /// manager/proxy remains held until didDisconnect/didFail, while a scan-only
    /// transport uses an explicit main-queue fence.
    func retireCurrentCentral() {
        let retiredAttempt = centralLifecycle.attempt ?? generation
        guard let transport = centralTransport else {
            // A second deactivate must not turn a still-quiescing lifecycle
            // back into idle and thereby permit a replacement manager early.
            guard pendingCentralRetirement == nil else { return }
            if centralLifecycle != .idle { centralLifecycle = .idle }
            return
        }
        centralLifecycle = .quiescing(retiredAttempt)
        scanRequestedWhileQuiescing = false
        let managerIdentity = transport.identity
        let peripheralKey: ObjectIdentifier?
        if let peripheralIdentity, let peripheralCallbackProxy {
            let key = ObjectIdentifier(peripheralIdentity)
            retiredPeripheralContexts[key] = XiaomiRemoteMicPeripheralContext(
                identity: peripheralIdentity,
                peripheral: peripheral,
                delegateProxy: peripheralCallbackProxy
            )
            peripheralKey = key
        } else {
            peripheralKey = nil
        }
        retiredCentralContexts[ObjectIdentifier(managerIdentity)] = transport
        pendingCentralRetirement = (managerIdentity, retiredAttempt, peripheralKey)
        centralTransport = nil

        transport.stopScan()
        if let peripheralIdentity {
            // Do not gate cancellation on CBPeripheral.state: a connecting
            // peripheral is a pending local connection and must be cancelled.
            transport.cancel(peripheral: peripheralIdentity)
        } else {
            scheduleCentralRetirementFence(
                managerIdentity: managerIdentity,
                attempt: retiredAttempt
            )
        }
    }

    /// A scan has no didDisconnect/didFail callback. Since the manager was
    /// created with `.main`, enqueueing this completion on the same queue is the
    /// explicit scan retirement boundary. Connection retirement uses its
    /// terminal central callback instead.
    func scheduleCentralRetirementFence(managerIdentity: AnyObject, attempt: UInt64) {
        let managerKey = ObjectIdentifier(managerIdentity)
        DispatchQueue.main.async { [weak self] in
            self?.finishCentralRetirement(managerKey: managerKey, attempt: attempt)
        }
    }

    func finishCentralRetirement(managerIdentity: AnyObject, attempt: UInt64) {
        finishCentralRetirement(managerKey: ObjectIdentifier(managerIdentity), attempt: attempt)
    }

    func finishCentralRetirement(managerKey: ObjectIdentifier, attempt: UInt64) {
        guard let pending = pendingCentralRetirement,
              pending.attempt == attempt,
              ObjectIdentifier(pending.identity) == managerKey else { return }
        let managerIdentity = pending.identity
        pendingCentralRetirement = nil
        retiredCentralContexts.removeValue(forKey: ObjectIdentifier(managerIdentity))
        if let peripheralKey = pending.peripheralKey,
           let context = retiredPeripheralContexts.removeValue(forKey: peripheralKey) {
            context.peripheral?.delegate = nil
        }
        centralLifecycle = .idle
        let waiters = retirementWaiters
        retirementWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard isActive, scanRequestedWhileQuiescing else { return }
        scanRequestedWhileQuiescing = false
        beginScan()
    }

    func resetPeripheral() {
        // A retired context owns the old peripheral/proxy until the central
        // terminal callback. For an ordinary reset there is no such context,
        // so detach immediately.
        if let peripheralIdentity,
           retiredPeripheralContexts[ObjectIdentifier(peripheralIdentity)] == nil {
            peripheral?.delegate = nil
        }
        peripheral = nil
        peripheralIdentity = nil
        activeConnectionAttempt = nil
        peripheralCallbackProxy = nil
        transmitCharacteristic = nil
        audioCharacteristic = nil
        controlCharacteristic = nil
        streamID = 0
    }

    /// Starts a new peripheral lifecycle and installs the source-bound route.
    /// CoreBluetooth itself does not expose the attempt id on delegate events;
    /// this proxy is the lifecycle boundary that supplies it.
    func beginPeripheralAttempt(
        _ attempt: UInt64,
        peripheral: CBPeripheral? = nil,
        peripheralIdentity: AnyObject? = nil
    ) {
        activeConnectionAttempt = attempt
        handshake.beginAttempt(attempt)
        let proxy = XiaomiRemoteMicPeripheralDelegateProxy(bridge: self, attempt: attempt)
        peripheralCallbackProxy = proxy
        self.peripheralIdentity = peripheralIdentity ?? peripheral
        if let peripheral {
            self.peripheral = peripheral
            peripheral.delegate = proxy
        }
    }
}
