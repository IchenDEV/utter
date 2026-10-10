import Foundation
import CoreBluetooth
import UtterContracts

extension XiaomiRemoteMicBridge {
    func connectToKnownRemote(using transport: XiaomiRemoteMicCentralTransport) -> Bool {
        let lookups: [(CBUUID, RemoteMicDiscoverySource)] = [
            (serviceUUID, .connectedVoiceService),
            (RemoteMicDeviceMatcher.hidServiceUUID, .connectedHID),
        ]
        for (service, source) in lookups {
            guard let known = transport.connectedPeripherals(withServices: [service])
                .first(where: { service == serviceUUID || RemoteMicDeviceMatcher.matches(name: $0.name) })
            else { continue }
            transport.delegateProxy.bindPeripheralIdentity(known.identity)
            pendingDiscoverySource = source
            routeCentralDidDiscover(
                managerIdentity: transport.identity,
                peripheralIdentity: known.identity,
                peripheral: known.identity as? CBPeripheral,
                advertisementData: [:],
                rssi: 0,
                sourceAttempt: nil
            )
            return state == .connecting
        }
        return false
    }
}
