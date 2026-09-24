import AVFoundation
import Foundation
import SoundAnalysis

enum SpeechActivityClassifier {
    static let minimumSpeechConfidence = 0.6
    private static let windowSeconds = 0.5
    private static let minimumFileSeconds = 0.75

    static func containsSpeech(at audioURL: URL?) async -> Bool {
        guard let audioURL, !Task.isCancelled else { return false }
        var paddedURL: URL?
        defer {
            if let paddedURL { try? FileManager.default.removeItem(at: paddedURL) }
        }

        do {
            let analysisURL = try preparedURL(audioURL, paddedURL: &paddedURL)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: windowSeconds, preferredTimescale: 16_000)
            let observer = SpeechClassificationObserver()
            let analyzer = try SNAudioFileAnalyzer(url: analysisURL)
            try analyzer.add(request, withObserver: observer)
            let completed = await withTaskCancellationHandler {
                await analyzer.analyze()
            } onCancel: {
                analyzer.cancelAnalysis()
            }
            let result = observer.result
            return completed && !Task.isCancelled && !result.failed
                && result.windows > 0 && result.maxSpeech >= minimumSpeechConfidence
        } catch {
            Log.error("[SpeechActivity] classification failed")
            return false
        }
    }

    private static func preparedURL(_ url: URL, paddedURL: inout URL?) throws -> URL {
        let source = try AVAudioFile(forReading: url)
        let format = source.processingFormat
        guard format.sampleRate > 0, source.length > 0 else { throw SpeechActivityError.invalidAudio }
        let requiredFrames = Int(ceil(minimumFileSeconds * format.sampleRate))
        guard source.length < requiredFrames else { return url }
        guard requiredFrames <= Int(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(requiredFrames)) else {
            throw SpeechActivityError.invalidAudio
        }
        try source.read(into: buffer)
        let readFrames = Int(buffer.frameLength)
        guard readFrames > 0, readFrames < requiredFrames else { throw SpeechActivityError.invalidAudio }

        let channels = Int(format.channelCount)
        if let data = buffer.floatChannelData {
            for channel in 0..<channels {
                for frame in readFrames..<requiredFrames { data[channel][frame] = 0 }
            }
        } else if let data = buffer.int16ChannelData {
            for channel in 0..<channels {
                for frame in readFrames..<requiredFrames { data[channel][frame] = 0 }
            }
        } else if let data = buffer.int32ChannelData {
            for channel in 0..<channels {
                for frame in readFrames..<requiredFrames { data[channel][frame] = 0 }
            }
        } else {
            throw SpeechActivityError.invalidAudio
        }
        buffer.frameLength = AVAudioFrameCount(requiredFrames)
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-speech-\(UUID().uuidString).wav")
        paddedURL = target
        let output = try AVAudioFile(
            forWriting: target,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try output.write(from: buffer)
        return target
    }
}

private enum SpeechActivityError: Error {
    case invalidAudio
}

private final class SpeechClassificationObserver: NSObject, SNResultsObserving {
    private let lock = NSLock()
    private var windows = 0
    private var maxSpeech = 0.0
    private var failed = false

    var result: (windows: Int, maxSpeech: Double, failed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (windows, maxSpeech, failed)
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let speech = result.classifications.first(where: { $0.identifier == "speech" })?.confidence ?? 0
        lock.lock()
        windows += 1
        maxSpeech = max(maxSpeech, speech)
        lock.unlock()
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock()
        failed = true
        lock.unlock()
    }

    func requestDidComplete(_ request: SNRequest) {}
}
