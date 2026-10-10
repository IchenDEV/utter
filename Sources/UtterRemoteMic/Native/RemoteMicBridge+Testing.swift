import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge {
    // MARK: - Test-only routing seams

    /// Test-only: reset to a clean state for routing tests.
    package func configureForTesting() {
        cancelExtend()
        cancelReconnect()
        cancelTimeout()
        if let transport = centralTransport {
            transport.stopScan()
            if let peripheralIdentity { transport.cancel(peripheral: peripheralIdentity) }
        }
        centralTransport = nil
        pendingCentralRetirement = nil
        for context in retiredPeripheralContexts.values {
            context.peripheral?.delegate = nil
        }
        retiredCentralContexts.removeAll()
        retiredPeripheralContexts.removeAll()
        centralLifecycle = .idle
        scanRequestedWhileQuiescing = false
        isActive = false
        resetPeripheral()
        handshake.reset()
        generation = 0
        state = .idle
    }

    /// Test-only: the factory is consumed by `activate()`/`installCentralTransport()`
    /// exactly like the production CoreBluetooth initializer. It is not a
    /// proxy-only injection seam.
    package func installCentralTransportFactoryForTesting(
        _ factory: @escaping () -> XiaomiRemoteMicCentralTransport
    ) {
        centralTransportFactory = factory
    }

    /// Test-only: the currently held production transport, including its
    /// non-nil manager identity and delegate proxy.
    package func centralTransportForTesting() -> XiaomiRemoteMicCentralTransport? {
        centralTransport
    }

    /// Test-only: drive the same central state route with a non-nil manager
    /// identity supplied by the production-created transport.
    package func simulateCentralStateForTesting(_ state: CBManagerState) {
        guard let transport = centralTransport else { return }
        routeCentralManagerDidUpdateState(
            managerIdentity: transport.identity,
            managerState: state,
            sourceAttempt: transport.delegateProxy.attempt
        )
    }

    /// Test-only: drive discovery through the production route with a
    /// non-nil peripheral identity. Returns the attempt bound by discovery.
    @discardableResult
    package func simulateCentralDiscoveryForTesting(peripheralIdentity: AnyObject) -> UInt64? {
        guard let transport = centralTransport else { return nil }
        transport.delegateProxy.bindPeripheralIdentity(peripheralIdentity)
        routeCentralDidDiscover(
            managerIdentity: transport.identity,
            peripheralIdentity: peripheralIdentity,
            peripheral: nil,
            advertisementData: [:],
            rssi: 0,
            sourceAttempt: transport.delegateProxy.attempt
        )
        return activeConnectionAttempt
    }

    /// Test-only: explicitly deliver the cancellation completion of the held
    /// transport. Production gets this signal from didDisconnect/didFail or a
    /// main-queue scan fence; tests inject it deterministically.
    package func completeCentralRetirementForTesting() {
        guard let pending = pendingCentralRetirement else { return }
        finishCentralRetirement(managerIdentity: pending.identity, attempt: pending.attempt)
    }

    /// Test-only: evidence for the ownership contract: a retired context is
    /// retained until completion, then released.
    package func retiredCentralContextCountForTesting() -> Int {
        retiredCentralContexts.count
    }

    /// Test-only: the old peripheral delegate/proxy is held through terminal
    /// cancellation, then released with the retired central context.
    package func retiredPeripheralContextCountForTesting() -> Int {
        retiredPeripheralContexts.count
    }

    /// Test-only: the production manager may not be created while this gate is
    /// pending, even when the feature is turned on again immediately.
    package func isCentralQuiescingForTesting() -> Bool {
        if case .quiescing = centralLifecycle { return true }
        return false
    }

    /// Test-only: simulate a connect and return the attempt it bound.
    @discardableResult
    package func simulateConnectForTesting() -> UInt64 {
        generation &+= 1
        let attempt = generation
        beginPeripheralAttempt(attempt)
        centralLifecycle = .connecting(attempt)
        state = .connecting
        return attempt
    }

    /// Test-only: simulate a reconnect on the same peripheral object. The new
    /// lifecycle gets a new source proxy; callers can retain the old proxy and
    /// deliver a late event through the production route.
    @discardableResult
    package func simulateReconnectSamePeripheralForTesting() -> UInt64 {
        simulateConnectForTesting()
    }

    /// Test-only: the attempt currently accepted for the lifecycle.
    package func attemptForCurrentPeripheralForTesting() -> UInt64? {
        activeConnectionAttempt
    }

    /// Test-only: retain the source envelope for a simulated lifecycle.
    package func callbackProxyForTesting() -> XiaomiRemoteMicPeripheralDelegateProxy? {
        peripheralCallbackProxy
    }

    /// Test-only: whether the lifecycle is still installed after a late event.
    package func isAttemptActiveForTesting(_ attempt: UInt64) -> Bool {
        activeConnectionAttempt == attempt && peripheralCallbackProxy?.attempt == attempt
    }

    /// Test-only: whether the source-bound central lifecycle is still current.
    package func isCentralAttemptActiveForTesting(_ attempt: UInt64) -> Bool {
        centralLifecycle.attempt == attempt
            && activeConnectionAttempt == attempt
            && handshake.accepts(attempt)
    }

    /// Test-only: whether the handshake still tracks `attempt`.
    package func acceptsAttemptForTesting(_ attempt: UInt64) -> Bool {
        handshake.accepts(attempt)
    }

    /// Test-only: send the capability request for the current attempt.
    package func simulateCapabilitiesRequestedForTesting() {
        handshake.markCapabilitiesRequested()
    }

    package func markActiveForTesting() {
        isActive = true
    }

    package func beginHostSessionForTesting() -> UInt64? {
        latchHostSession()
    }
}
