import Foundation
import CoreBluetooth
import Combine
import UtterContracts

/// The bridge owns one transport for one central lifecycle. Keeping the
/// transport behind this seam lets tests exercise the production initializer,
/// strong manager/proxy ownership, identity gates, and cancellation completion
/// without manufacturing a CoreBluetooth object.
package protocol XiaomiRemoteMicCentralTransport: AnyObject {
    var identity: AnyObject { get }
    var delegateProxy: XiaomiRemoteMicCentralDelegateProxy { get }
    var state: CBManagerState { get }

    func stopScan()
    func scanForPeripherals(withServices services: [CBUUID], options: [String: Any]?)
    func connectedPeripherals(withServices services: [CBUUID]) -> [RemoteMicKnownPeripheral]
    func connect(to peripheral: AnyObject)
    func cancel(peripheral: AnyObject)
}

extension XiaomiRemoteMicCentralTransport {
    package func connectedPeripherals(withServices services: [CBUUID]) -> [RemoteMicKnownPeripheral] { [] }
}

package struct RemoteMicKnownPeripheral {
    package let identity: AnyObject
    package let name: String?
    package init(identity: AnyObject, name: String?) { self.identity = identity; self.name = name }
}

/// Production transport. The manager and its weak delegate are held together
/// so an old manager can still deliver a terminal callback to its old proxy
/// while retirement is waiting for cancellation to complete.
final class XiaomiRemoteMicCoreBluetoothCentralTransport: XiaomiRemoteMicCentralTransport {
    let manager: CBCentralManager
    let delegateProxy: XiaomiRemoteMicCentralDelegateProxy

    var identity: AnyObject { manager }
    var state: CBManagerState { manager.state }

    init(bridge: XiaomiRemoteMicBridge) {
        let proxy = XiaomiRemoteMicCentralDelegateProxy(bridge: bridge)
        delegateProxy = proxy
        manager = CBCentralManager(
            delegate: proxy,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        proxy.bindManagerIdentity(manager)
    }

    func stopScan() {
        manager.stopScan()
    }

    func scanForPeripherals(withServices services: [CBUUID], options: [String: Any]?) {
        manager.scanForPeripherals(withServices: services, options: options)
    }

    func connectedPeripherals(withServices services: [CBUUID]) -> [RemoteMicKnownPeripheral] {
        manager.retrieveConnectedPeripherals(withServices: services)
            .map { RemoteMicKnownPeripheral(identity: $0, name: $0.name) }
    }

    func connect(to peripheral: AnyObject) {
        guard let peripheral = peripheral as? CBPeripheral else { return }
        manager.connect(peripheral, options: nil)
    }

    func cancel(peripheral: AnyObject) {
        guard let peripheral = peripheral as? CBPeripheral else { return }
        manager.cancelPeripheralConnection(peripheral)
    }
}

/// CoreBluetooth keeps a peripheral's delegate weak. Keep the old peripheral
/// and its source proxy together until the central's cancellation callback has
/// arrived; otherwise a queued didDisconnect/didFail event can disappear or be
/// delivered to a replacement lifecycle.
final class XiaomiRemoteMicPeripheralContext {
    let identity: AnyObject
    let peripheral: CBPeripheral?
    let delegateProxy: XiaomiRemoteMicPeripheralDelegateProxy

    init(
        identity: AnyObject,
        peripheral: CBPeripheral?,
        delegateProxy: XiaomiRemoteMicPeripheralDelegateProxy
    ) {
        self.identity = identity
        self.peripheral = peripheral
        self.delegateProxy = delegateProxy
    }
}

enum XiaomiRemoteMicCentralLifecycle: Equatable {
    case idle
    case scanning(UInt64)
    case connecting(UInt64)
    case connected(UInt64)
    case quiescing(UInt64)

    var attempt: UInt64? {
        switch self {
        case .idle: return nil
        case let .scanning(attempt), let .connecting(attempt),
             let .connected(attempt), let .quiescing(attempt):
            return attempt
        }
    }
}
