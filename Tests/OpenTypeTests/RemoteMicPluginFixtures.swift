import CoreBluetooth
import Foundation
import UtterContracts
import UtterRuntime
@testable import UtterRemoteMic

final class ScopedRemoteTransport: XiaomiRemoteMicCentralTransport {
    let identity: AnyObject = NSObject()
    let delegateProxy: XiaomiRemoteMicCentralDelegateProxy
    var state: CBManagerState = .poweredOn
    var onCancel: (() -> Void)?
    var cancelCount = 0

    init(bridge: XiaomiRemoteMicBridge) {
        delegateProxy = XiaomiRemoteMicCentralDelegateProxy(bridge: bridge)
        delegateProxy.bindManagerIdentity(identity)
    }

    func stopScan() {}
    func scanForPeripherals(withServices services: [CBUUID], options: [String: Any]?) {}
    func connect(to peripheral: AnyObject) { delegateProxy.bindPeripheralIdentity(peripheral) }
    func cancel(peripheral: AnyObject) {
        cancelCount += 1
        onCancel?()
    }
}

@MainActor
final class RemoteLifetimeSignal {
    private var signalled = false
    private var waiter: CheckedContinuation<Void, Never>?
    func send() {
        signalled = true
        waiter?.resume()
        waiter = nil
    }
    func wait() async {
        if signalled { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

struct RemotePluginDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}

final class RemotePluginSettings: SettingsService {
    var values = SettingsValues()
    var observers: [UUID: (SettingsValues) -> Void] = [:]
    func update(_ mutation: (inout SettingsValues) -> Void) {
        mutation(&values)
        for observer in Array(observers.values) { observer(values) }
    }
    func observe(_ callback: @escaping (SettingsValues) -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }
    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    func resetDeveloperHTTPToken() {}
}
