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
        cancelExtend()
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
        cancelExtend()
        hostInitiated = false
        streamAnnounced = false
        preRoll.reset()
        accumulator.reset()
        pendingSync = nil
        decoder.reset()
    }

    func startExtending() {
        extendTask?.cancel()
        extendTask = ownedTask { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(RemoteMicProtocol.extendInterval * 1_000_000_000))
                guard let self, !Task.isCancelled, self.session.isLive, self.microphoneOpened,
                      let command = RemoteMicProtocol.microphoneExtend(
                          version: self.capabilities.version,
                          sessionID: self.streamID
                      ) else { return }
                _ = self.write(command)
            }
        }
    }

    func cancelExtend() {
        extendTask?.cancel()
        extendTask = nil
    }
}
