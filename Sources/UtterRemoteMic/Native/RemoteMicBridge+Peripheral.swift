import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge {
    func routeDidDiscoverServices(
        _ peripheral: CBPeripheral,
        error: Error?,
        attempt: UInt64
    ) {
        guard acceptsPeripheralCallback(peripheral, attempt: attempt), error == nil else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            failAttempt(reason: L("remote_mic.error.service_missing"))
            return
        }
        peripheral.discoverCharacteristics(
            [CBUUID(string: RemoteMicProtocol.transmitUUID),
             CBUUID(string: RemoteMicProtocol.audioUUID),
             CBUUID(string: RemoteMicProtocol.controlUUID)],
            for: service
        )
        if let info = peripheral.services?.first(where: {
            $0.uuid == RemoteMicDeviceMatcher.deviceInformationServiceUUID
        }) {
            peripheral.discoverCharacteristics([RemoteMicDeviceMatcher.modelNumberUUID], for: info)
        } else {
            handleModelNumber(nil, attempt: attempt)
        }
    }

    func routeDidDiscoverCharacteristics(
        _ peripheral: CBPeripheral,
        service: CBService,
        error: Error?,
        attempt: UInt64
    ) {
        guard acceptsPeripheralCallback(peripheral, attempt: attempt) else { return }
        if service.uuid == RemoteMicDeviceMatcher.deviceInformationServiceUUID {
            guard error == nil else {
                failAttempt(reason: L("remote_mic.error.model_unreadable"))
                return
            }
            if let model = service.characteristics?.first(where: {
                $0.uuid == RemoteMicDeviceMatcher.modelNumberUUID
            }) {
                peripheral.readValue(for: model)
            } else {
                handleModelNumber(nil, attempt: attempt)
            }
            return
        }
        guard error == nil else { return }
        let transmit = RemoteMicProtocol.transmitUUID.uppercased()
        let audio = RemoteMicProtocol.audioUUID.uppercased()
        let control = RemoteMicProtocol.controlUUID.uppercased()
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid.uuidString.uppercased() {
            case transmit:
                transmitCharacteristic = characteristic
                handshake.registerCharacteristic(.transmit)
            case audio:
                audioCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case control:
                controlCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        guard transmitCharacteristic != nil,
              audioCharacteristic != nil,
              controlCharacteristic != nil else {
            failAttempt(reason: L("remote_mic.error.characteristic_missing"))
            return
        }
        // Capabilities wait for didUpdateNotificationStateFor on both channels.
        requestCapabilitiesIfReady()
    }

    func routeDidUpdateNotificationState(
        _ peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        error: Error?,
        attempt: UInt64
    ) {
        guard acceptsPeripheralCallback(peripheral, attempt: attempt), error == nil else { return }
        guard characteristic.isNotifying else { return }
        switch characteristic.uuid.uuidString.uppercased() {
        case RemoteMicProtocol.audioUUID.uppercased():
            handshake.confirmSubscription(.audio)
        case RemoteMicProtocol.controlUUID.uppercased():
            handshake.confirmSubscription(.control)
        default:
            return
        }
        requestCapabilitiesIfReady()
    }

    func routeDidUpdateValue(
        _ peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        error: Error?,
        attempt: UInt64
    ) {
        // A reused CBPeripheral object can deliver a late value from a previous
        // attempt; attribute it to the attempt that raised it and drop it when
        // this handshake no longer tracks that attempt.
        guard acceptsPeripheralCallback(peripheral, attempt: attempt) else { return }
        if characteristic.uuid == RemoteMicDeviceMatcher.modelNumberUUID {
            guard !handshake.decoderConfigured else { return }
            guard error == nil, let data = characteristic.value else {
                failAttempt(reason: L("remote_mic.error.model_unreadable"))
                return
            }
            handleModelNumber(data, attempt: attempt)
            return
        }
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid.uuidString.uppercased() {
        case RemoteMicProtocol.controlUUID.uppercased():
            handleControl(data, attempt: attempt)
        case RemoteMicProtocol.audioUUID.uppercased():
            handleAudio(data, attempt: attempt)
        default:
            break
        }
    }

    /// The common gate for every CBPeripheralDelegate callback. Unlike the old
    /// `attempt(for:)` lookup, the attempt here came from the delegate proxy
    /// that was installed for the connection lifecycle.
    func acceptsPeripheralCallback(_ peripheral: CBPeripheral?, attempt: UInt64) -> Bool {
        guard activeConnectionAttempt == attempt,
              peripheralCallbackProxy?.attempt == attempt,
              handshake.accepts(attempt) else { return false }
        if let peripheral {
            guard peripheral === self.peripheral else { return false }
        }
        return true
    }

    /// Test-only event route used by `XiaomiRemoteMicPeripheralDelegateProxy`.
    /// It intentionally enters the same attempt gate and handlers as production
    /// delegate callbacks; it only omits unavailable CoreBluetooth value types.
    func routeTestCallback(
        _ callback: XiaomiRemoteMicTestCallback,
        attempt: UInt64
    ) {
        guard acceptsPeripheralCallback(nil, attempt: attempt) else { return }
        switch callback {
        case .disconnect:
            handleDisconnect()
        case let .control(data):
            handleControl(data, attempt: attempt)
        case let .audio(data):
            handleAudio(data, attempt: attempt)
        case let .modelNumber(data):
            handleModelNumber(data, attempt: attempt)
        }
    }
}
