import Foundation
import CoreBluetooth
import Combine
import UtterContracts

/// The delegate callbacks below do not contain a CoreBluetooth connection id.
/// A proxy is therefore installed for each connection lifecycle and captures
/// the attempt at the point where CoreBluetooth is wired to the bridge. The
/// bridge never looks up an attempt from the current peripheral when routing a
/// callback; the proxy is the callback's source envelope.
package enum XiaomiRemoteMicTestCallback: Equatable {
    case disconnect
    case control(Data)
    case audio(Data)
    case modelNumber(Data?)
}

/// Central callbacks have the same source problem as peripheral callbacks:
/// CoreBluetooth supplies the peripheral object, but no connection-attempt id.
/// The production central delegate proxy captures the id when a discovered
/// peripheral is connected. Tests use the same proxy route to deliver a late
/// event from an older central lifecycle.
package enum XiaomiRemoteMicCentralTestCallback: Equatable {
    case didConnect
    case didFailToConnect
    case didDisconnect
}

package final class XiaomiRemoteMicPeripheralDelegateProxy: NSObject, CBPeripheralDelegate {
    package weak var bridge: XiaomiRemoteMicBridge?
    package let attempt: UInt64

    package init(bridge: XiaomiRemoteMicBridge, attempt: UInt64) {
        self.bridge = bridge
        self.attempt = attempt
        super.init()
    }

    package func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        bridge?.routeDidDiscoverServices(peripheral, error: error, attempt: attempt)
    }

    package func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        bridge?.routeDidDiscoverCharacteristics(
            peripheral,
            service: service,
            error: error,
            attempt: attempt
        )
    }

    package func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        bridge?.routeDidUpdateNotificationState(
            peripheral,
            characteristic: characteristic,
            error: error,
            attempt: attempt
        )
    }

    package func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        bridge?.routeDidUpdateValue(
            peripheral,
            characteristic: characteristic,
            error: error,
            attempt: attempt
        )
    }

    /// Drives the same bridge route as the CoreBluetooth delegate methods, but
    /// without manufacturing CoreBluetooth objects. This is the test entry for
    /// a callback that was raised by this particular lifecycle proxy.
    package func deliverForTesting(_ callback: XiaomiRemoteMicTestCallback) {
        bridge?.routeTestCallback(callback, attempt: attempt)
    }
}

/// One central manager is used for one connection lifecycle. A
/// `CBCentralManagerDelegate` callback has no source id, so reusing a manager
/// would make a late callback indistinguishable from the replacement attempt.
/// Keeping this proxy with the manager gives every callback the lifecycle that
/// actually owned that manager. The scan phase is unbound; it is bound exactly
/// when `didDiscover` starts the connection.
package final class XiaomiRemoteMicCentralDelegateProxy: NSObject, CBCentralManagerDelegate {
    package weak var bridge: XiaomiRemoteMicBridge?
    package private(set) var attempt: UInt64?
    package private(set) var sourceManagerIdentity: AnyObject?
    package private(set) var sourcePeripheralIdentity: AnyObject?

    package init(bridge: XiaomiRemoteMicBridge) {
        self.bridge = bridge
        super.init()
    }

    package func bind(to attempt: UInt64) {
        guard self.attempt == nil else { return }
        self.attempt = attempt
    }

    package func bindManagerIdentity(_ identity: AnyObject) {
        guard sourceManagerIdentity == nil else { return }
        sourceManagerIdentity = identity
    }

    package func bindPeripheralIdentity(_ identity: AnyObject) {
        sourcePeripheralIdentity = identity
    }

    package func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bindManagerIdentity(central)
        bridge?.routeCentralManagerDidUpdateState(
            managerIdentity: central,
            managerState: central.state,
            sourceAttempt: attempt
        )
    }

    package func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard RemoteMicDeviceMatcher.isCandidate(
            peripheralName: peripheral.name,
            advertisedName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            advertisedServiceUUIDs: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        ) else { return }
        bindManagerIdentity(central)
        bindPeripheralIdentity(peripheral)
        bridge?.routeCentralDidDiscover(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI,
            sourceAttempt: attempt
        )
    }

    package func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        bindManagerIdentity(central)
        bindPeripheralIdentity(peripheral)
        bridge?.routeCentralDidConnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            sourceAttempt: attempt
        )
    }

    package func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        bindManagerIdentity(central)
        bindPeripheralIdentity(peripheral)
        bridge?.routeCentralDidFailToConnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            error: error,
            sourceAttempt: attempt
        )
    }

    package func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        bindManagerIdentity(central)
        bindPeripheralIdentity(peripheral)
        bridge?.routeCentralDidDisconnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            error: error,
            sourceAttempt: attempt
        )
    }

    /// Test-only entry that uses the same source-bound route as the delegate
    /// methods above, without manufacturing CoreBluetooth objects.
    package func deliverForTesting(_ callback: XiaomiRemoteMicCentralTestCallback) {
        guard let attempt,
              let sourceManagerIdentity,
              let sourcePeripheralIdentity else { return }
        bridge?.routeCentralCallbackForTesting(
            callback,
            attempt: attempt,
            managerIdentity: sourceManagerIdentity,
            peripheralIdentity: sourcePeripheralIdentity
        )
    }
}
