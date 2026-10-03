import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge: CBCentralManagerDelegate {
    package func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // The bridge remains conformant for compatibility, but production
        // managers use XiaomiRemoteMicCentralDelegateProxy. An unbound direct
        // callback is deliberately not accepted for connection events.
        routeCentralManagerDidUpdateState(
            managerIdentity: central,
            managerState: central.state,
            sourceAttempt: nil
        )
    }

    package func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        routeCentralDidDiscover(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI,
            sourceAttempt: nil
        )
    }

    package func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        routeCentralDidConnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            sourceAttempt: nil
        )
    }

    package func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        routeCentralDidFailToConnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            error: error,
            sourceAttempt: nil
        )
    }

    package func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        routeCentralDidDisconnect(
            managerIdentity: central,
            peripheralIdentity: peripheral,
            peripheral: peripheral,
            error: error,
            sourceAttempt: nil
        )
    }
}
