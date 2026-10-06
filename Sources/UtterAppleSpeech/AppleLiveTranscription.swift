import AVFoundation
import Foundation
@preconcurrency import Speech
import UtterContracts

/// Recognition that runs while the microphone is still open. Buffers go in from the capture tap; the draft
/// text comes out through `onDraft` as the recognizer revises it, and `finish()` returns the final text.
package final class AppleLiveTranscription: @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let results: Task<String, Error>
    private let converter: AVAudioConverter
    private let target: AVAudioFormat

    private init(analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation, results: Task<String, Error>,
                 converter: AVAudioConverter, target: AVAudioFormat) {
        self.analyzer = analyzer; self.input = input; self.results = results
        self.converter = converter; self.target = target
    }

    /// Nil when this locale has no on-device transcriber that reports interim results; the caller then
    /// transcribes the recorded file after the recording ends.
    package static func start(locale: Locale, source: AVAudioFormat, context: SpeechRecognitionContext,
                              onDraft: @escaping @Sendable (String) -> Void) async throws -> AppleLiveTranscription? {
        guard SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        guard await AssetInventory.status(forModules: [transcriber]) == .installed,
              let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let converter = AVAudioConverter(from: source, to: target) else { return nil }
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .lingering))
        if !context.phrases.isEmpty {
            let analysis = AnalysisContext()
            analysis.contextualStrings[.general] = context.phrases
            try await analyzer.setContext(analysis)
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let results = Task<String, Error> {
            var finalized = "", volatile = ""
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal { finalized += text; volatile = "" } else { volatile = text }
                onDraft(finalized + volatile)
            }
            return finalized
        }
        do { try await analyzer.start(inputSequence: stream) }
        catch { results.cancel(); continuation.finish(); throw error }
        return AppleLiveTranscription(analyzer: analyzer, input: continuation, results: results, converter: converter, target: target)
    }

    /// Called from the audio thread; converts and queues the buffer.
    package func append(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false
        var failure: NSError?
        converter.convert(to: output, error: &failure) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData
            return buffer
        }
        guard failure == nil, output.frameLength > 0 else { return }
        input.yield(AnalyzerInput(buffer: output))
    }

    /// Ends the input, lets the recognizer settle its last words, and returns everything it finalized.
    package func finish() async throws -> String {
        input.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return try await results.value
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    package func cancel() {
        input.finish()
        results.cancel()
        Task { await analyzer.cancelAndFinishNow() }
    }
}
