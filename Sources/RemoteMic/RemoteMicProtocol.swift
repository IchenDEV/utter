import Foundation

/// Audio Transport Voice (ATVV) profile pieces used by the Xiaomi Bluetooth
/// Remote 2 Pro.
///
/// The GATT service, the control opcodes, and the IMA/DVI ADPCM sample format
/// are open specifications; this is an independent implementation of those
/// specifications for a single 16 kHz mono stream, not a copy of any app.
enum RemoteMicProtocol {
    static let serviceUUID = "AB5E0001-5A21-4F05-BC7D-AF01F617B664"
    static let transmitUUID = "AB5E0002-5A21-4F05-BC7D-AF01F617B664"
    static let audioUUID = "AB5E0003-5A21-4F05-BC7D-AF01F617B664"
    static let controlUUID = "AB5E0004-5A21-4F05-BC7D-AF01F617B664"

    static let supportedSampleRate: Double = 16_000
    static let defaultFrameSize = 120
    static let defaultGainDB: Double = 12

    /// Host -> remote capability request (`GET_CAPABILITIES` for ATVV v1.0).
    static let getCapabilities = Data([0x0A, 0x01, 0x00, 0x00, 0x03, 0x03])

    static func supportsAudio(sampleRate: Double) -> Bool {
        sampleRate == supportedSampleRate
    }

    static func microphoneOpen(version: UInt16, codec: UInt8) -> Data {
        version >= 0x0100 ? Data([0x0C, 0x00]) : Data([0x0C, 0x00, codec])
    }

    static func microphoneClose(version: UInt16, sessionID: UInt8) -> Data {
        version >= 0x0100 ? Data([0x0D, sessionID]) : Data([0x0D])
    }
}

/// Remote capabilities reported by the `0x0B` control response.
struct RemoteMicCapabilities: Equatable {
    var version: UInt16
    var codecs: UInt8
    var interaction: UInt8
    var frameSize: Int
    var selectedCodec: UInt8
    var sampleRate: Double

    static let `default` = RemoteMicCapabilities(
        version: 0x0100,
        codecs: 0x02,
        interaction: 0x03,
        frameSize: RemoteMicProtocol.defaultFrameSize,
        selectedCodec: 0x02,
        sampleRate: RemoteMicProtocol.supportedSampleRate
    )

    /// Parses the `0x0B` payload. Returns `nil` when it is not a capability frame.
    static func parse(_ data: Data) -> RemoteMicCapabilities? {
        let bytes = Array(data)
        guard bytes.count >= 7, bytes[0] == 0x0B else { return nil }

        let version = UInt16(bytes[1]) << 8 | UInt16(bytes[2])
        var codecs: UInt8
        var interaction: UInt8
        if version >= 0x0100 {
            codecs = bytes[3]
            interaction = bytes[4]
            if codecs == 0, bytes.count >= 9, bytes[4] & 0x03 != 0 {
                codecs = bytes[4]
                interaction = 0x03
            }
        } else {
            guard bytes.count >= 9 else { return nil }
            codecs = bytes[4]
            interaction = 0
        }

        let frameSize = Int(bytes[5]) << 8 | Int(bytes[6])
        let selectedCodec: UInt8 = codecs & 0x02 != 0 ? 0x02 : 0x01
        return RemoteMicCapabilities(
            version: version,
            codecs: codecs,
            interaction: interaction,
            frameSize: frameSize == 0 ? RemoteMicProtocol.defaultFrameSize : frameSize,
            selectedCodec: selectedCodec,
            sampleRate: selectedCodec == 0x02 ? RemoteMicProtocol.supportedSampleRate : 8_000
        )
    }
}

/// Control opcodes on the ATVV control characteristic.
enum RemoteMicControlOpcode: UInt8 {
    case streamStop = 0x00
    case streamStart = 0x04
    case microphoneOpenRequest = 0x08
    case capabilities = 0x0B
    case sync = 0x0A
}

/// Stateful IMA/DVI ADPCM decoder. The remote encodes four-bit nibbles per
/// sample; the sequence's predictor and step index persist across frames and can
/// be reset by a sync packet.
final class RemoteMicADPCMDecoder {
    private static let stepTable: [Int] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
        34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
        143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
        494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411,
        1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026,
        4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
        11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623,
        27086, 29794, 32767,
    ]
    private static let indexTable = [-1, -1, -1, -1, 2, 4, 6, 8]

    private(set) var predictor = 0
    private(set) var stepIndex = 0

    func reset(predictor: Int = 0, stepIndex: Int = 0) {
        self.predictor = min(32_767, max(-32_768, predictor))
        self.stepIndex = min(88, max(0, stepIndex))
    }

    /// Decodes high-nibble-first, the RC003/`MI RC` ordering.
    func decode(_ data: Data) -> [Int16] {
        var samples: [Int16] = []
        samples.reserveCapacity(data.count * 2)
        for byte in data {
            samples.append(decodeNibble(Int(byte >> 4)))
            samples.append(decodeNibble(Int(byte & 0x0F)))
        }
        return samples
    }

    private func decodeNibble(_ nibble: Int) -> Int16 {
        let step = Self.stepTable[stepIndex]
        var difference = step >> 3
        if nibble & 1 != 0 { difference += step >> 2 }
        if nibble & 2 != 0 { difference += step >> 1 }
        if nibble & 4 != 0 { difference += step }

        predictor += nibble & 8 != 0 ? -difference : difference
        predictor = min(32_767, max(-32_768, predictor))
        stepIndex += Self.indexTable[nibble & 7]
        stepIndex = min(88, max(0, stepIndex))
        return Int16(predictor)
    }
}

/// Three-point smoothing plus a bounded gain, applied after decoding.
enum RemoteMicPCM {
    static func process(_ input: [Int16], gainDB: Double) -> [Int16] {
        guard !input.isEmpty else { return [] }
        var filtered = input.map(Int.init)
        if input.count >= 3 {
            for index in 1..<(input.count - 1) {
                filtered[index] = (
                    Int(input[index - 1]) + 2 * Int(input[index]) + Int(input[index + 1])
                ) >> 2
            }
        }
        let finiteGain = gainDB.isFinite ? gainDB : 0
        let gain = pow(10.0, min(24.0, max(-24.0, finiteGain)) / 20.0)
        return filtered.map { value in
            Int16(min(32_767, max(-32_768, Int((Double(value) * gain).rounded()))))
        }
    }
}

/// Reassembles the remote's declared fixed-size audio frames from the byte
/// stream delivered by CoreBluetooth notifications.
struct RemoteMicFrameAccumulator {
    private(set) var pending = Data()

    mutating func append(_ data: Data, frameSize: Int) -> [Data] {
        guard frameSize > 0 else { return [] }
        pending.append(data)
        var frames: [Data] = []
        while pending.count >= frameSize {
            frames.append(Data(pending.prefix(frameSize)))
            pending.removeFirst(frameSize)
        }
        return frames
    }

    mutating func reset() {
        pending.removeAll(keepingCapacity: false)
    }
}
