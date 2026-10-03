import Foundation
import CoreBluetooth
import Combine
import UtterContracts

extension XiaomiRemoteMicBridge {
    // MARK: - Control

    func openMicrophoneIfNeeded() {
        guard !microphoneOpened else { return }
        let command = RemoteMicProtocol.microphoneOpen(
            version: capabilities.version,
            codec: capabilities.selectedCodec
        )
        guard write(command) else { return }
        microphoneOpened = true
    }

    func closeMicrophoneIfNeeded() {
        guard microphoneOpened else { return }
        _ = write(RemoteMicProtocol.microphoneClose(
            version: capabilities.version,
            sessionID: streamID
        ))
        microphoneOpened = false
        streamID = 0
    }

    func write(_ data: Data) -> Bool {
        guard let peripheral, let transmitCharacteristic else { return false }
        let type: CBCharacteristicWriteType =
            transmitCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: transmitCharacteristic, type: type)
        return true
    }

    func resetStream() {
        preRoll.reset()
        accumulator.reset()
        pendingSync = nil
        decoder.reset()
    }
}
