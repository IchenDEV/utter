import AVFoundation
import Foundation

enum QwenAudioPreprocessor {
    static let sampleRate = 16_000.0

    static func withPreparedAudio<T>(
        from sourceURL: URL,
        operation: (URL) async throws -> T
    ) async throws -> T {
        let preparedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenType-QwenASR-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: preparedURL) }

        do {
            try convertToPCM16kMono(from: sourceURL, to: preparedURL)
        } catch {
            Log.error("[Qwen3ASR] audio preprocessing failed: \(error.localizedDescription)")
            throw QwenAudioPreprocessorError.conversionFailed
        }

        return try await operation(preparedURL)
    }

    private static func convertToPCM16kMono(from sourceURL: URL, to outputURL: URL) throws {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = sourceFile.processingFormat
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw AudioConversionError.converterCreationFailed
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioConversionError.outputBufferCreationFailed
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
            throw AudioConversionError.converterCreationFailed
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        try convert(
            sourceFile: sourceFile,
            sourceFormat: sourceFormat,
            outputFile: outputFile,
            outputFormat: outputFormat,
            converter: converter
        )
    }

    private static func convert(
        sourceFile: AVAudioFile,
        sourceFormat: AVAudioFormat,
        outputFile: AVAudioFile,
        outputFormat: AVAudioFormat,
        converter: AVAudioConverter
    ) throws {
        let outputFrameCapacity: AVAudioFrameCount = 4_096
        var reachedEndOfInput = false

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCapacity
            ) else {
                throw AudioConversionError.outputBufferCreationFailed
            }

            var readError: Error?
            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &conversionError
            ) { requestedFrames, inputStatus in
                guard !reachedEndOfInput else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }

                let remainingFrames = sourceFile.length - sourceFile.framePosition
                guard remainingFrames > 0 else {
                    reachedEndOfInput = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }

                let frameCount = min(
                    max(requestedFrames, 1),
                    AVAudioFrameCount(remainingFrames)
                )
                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFormat,
                    frameCapacity: frameCount
                ) else {
                    readError = AudioConversionError.outputBufferCreationFailed
                    reachedEndOfInput = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }

                do {
                    try sourceFile.read(into: inputBuffer, frameCount: frameCount)
                } catch {
                    readError = error
                    reachedEndOfInput = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }

                guard inputBuffer.frameLength > 0 else {
                    reachedEndOfInput = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inputBuffer
            }

            if let readError { throw readError }
            if let conversionError { throw conversionError }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }

            switch status {
            case .haveData:
                continue
            case .inputRanDry:
                if reachedEndOfInput, outputBuffer.frameLength == 0 { return }
            case .endOfStream:
                return
            case .error:
                throw AudioConversionError.conversionFailed
            @unknown default:
                throw AudioConversionError.conversionFailed
            }
        }
    }
}

enum QwenAudioPreprocessorError: LocalizedError {
    case conversionFailed

    var errorDescription: String? {
        L("error.local_asr_audio_conversion")
    }
}
