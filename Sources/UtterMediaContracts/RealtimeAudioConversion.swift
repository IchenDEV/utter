import AVFoundation
import Foundation

extension AVAudioPCMBuffer {
    package func copied() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        ) else {
            return nil
        }

        copy.frameLength = frameLength

        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard
                let source = floatChannelData,
                let destination = copy.floatChannelData
            else {
                return nil
            }

            let byteCount = Int(frameLength) * MemoryLayout<Float>.size
            for channel in 0..<Int(format.channelCount) {
                memcpy(destination[channel], source[channel], byteCount)
            }
        case .pcmFormatInt16:
            guard
                let source = int16ChannelData,
                let destination = copy.int16ChannelData
            else {
                return nil
            }

            let byteCount = Int(frameLength) * MemoryLayout<Int16>.size
            for channel in 0..<Int(format.channelCount) {
                memcpy(destination[channel], source[channel], byteCount)
            }
        default:
            return nil
        }

        return copy
    }
}

package struct StreamingAudioChunk {
    package let samples: [Float]
    package init(samples: [Float]) { self.samples = samples }

    package var sampleCount: Int { samples.count }
    package var pcm16Data: Data { RealtimeAudioConverter.pcm16Data(from: samples) }
}

package final class RealtimeAudioConverter {
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    package init?(
        inputFormat: AVAudioFormat,
        outputCommonFormat: AVAudioCommonFormat,
        sampleRate: Double = 16_000,
        channels: AVAudioChannelCount = 1,
        interleaved: Bool
    ) {
        guard let outputFormat = AVAudioFormat(
            commonFormat: outputCommonFormat,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: interleaved
        ) else {
            return nil
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
    }

    package func convertToPCMData(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let converted = try convertBuffer(buffer)
        guard let data = converted.int16ChannelData else { return Data() }
        let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: data[0], count: byteCount)
    }

    package func convertToFloatArray(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let converted = try convertBuffer(buffer)
        guard let data = converted.floatChannelData else { return [] }
        let count = Int(converted.frameLength)
        return Array(UnsafeBufferPointer(start: data[0], count: count))
    }

    package func convertBuffer(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw AudioConversionError.outputBufferCreationFailed
        }

        var sourceBuffer: AVAudioPCMBuffer? = buffer
        var conversionError: NSError?

        converter.reset()
        _ = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            guard let currentBuffer = sourceBuffer else {
                outStatus.pointee = .endOfStream
                return nil
            }

            outStatus.pointee = .haveData
            sourceBuffer = nil
            return currentBuffer
        }

        if let conversionError {
            throw conversionError
        }
        return outputBuffer
    }

    package static func pcm16Data(from samples: [Float]) -> Data {
        guard !samples.isEmpty else { return Data() }

        var values: [Int16] = []
        values.reserveCapacity(samples.count)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            values.append(Int16((clamped * Float(Int16.max)).rounded()).littleEndian)
        }
        return values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}

package final class StreamingAudioNormalizer {
    private let floatConverter: RealtimeAudioConverter

    package init?(inputFormat: AVAudioFormat) {
        guard let floatConverter = RealtimeAudioConverter(
            inputFormat: inputFormat,
            outputCommonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else {
            return nil
        }

        self.floatConverter = floatConverter
    }

    package func convert(_ buffer: AVAudioPCMBuffer) throws -> StreamingAudioChunk {
        let converted = try floatConverter.convertBuffer(buffer)
        guard let data = converted.floatChannelData else {
            return StreamingAudioChunk(samples: [])
        }

        let count = Int(converted.frameLength)
        let samples = Array(UnsafeBufferPointer(start: data[0], count: count))
        return StreamingAudioChunk(samples: samples)
    }
}

package enum AudioConversionError: LocalizedError {
    case converterCreationFailed
    case outputBufferCreationFailed
    case conversionFailed
}
