import UtterMediaContracts
import UtterContracts
import Foundation
import AVFoundation
import WhisperKit
import CoreML

package final class WhisperEngine: SpeechEngine, @unchecked Sendable {
    let files: any ModelFilesService
    let access: any ModelResourceAccess
    let log: Log
    var closed = false
    var whisperKit: WhisperKit?
    let modelName: String?
    package internal(set) var isReady = false
    package internal(set) var isLoading = false
    var loadError: String?
    var preparationProgress: (SpeechModelProgress) -> Void = { _ in }
    private var retiredStreams: [WhisperStreamingSession] = []
    private var streamingSession: WhisperStreamingSession?
    private let recognitionContextLock = NSLock()
    private var recognitionContext = SpeechRecognitionContext.empty

    package init(modelName: String = "large-v3", files: any ModelFilesService, access: any ModelResourceAccess, log: Log) {
        self.files = files
        self.access = access
        self.log = log
        self.modelName = modelName.isEmpty ? nil : modelName
    }

    package func prepare() async {
        let retired = retiredStreams
        retiredStreams.removeAll()
        for stream in retired { await stream.shutdown() }
        if !isReady, !closed {
            do { try await loadModel(progress: preparationProgress) }
            catch { loadError = error.localizedDescription }
        }
    }

    package var supportsStreaming: Bool { true }

    package func configureRecognition(context: SpeechRecognitionContext) {
        recognitionContextLock.lock()
        defer { recognitionContextLock.unlock() }
        recognitionContext = context
    }

    package func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        guard let whisperKit, isReady else { return }
        let options = decodingOptions(
            language: language,
            temperatureFallbackCount: 1
        )
        streamingSession = WhisperStreamingSession(
            whisperKit: whisperKit,
            language: language,
            partialHandler: onPartialResult,
            optionsBuilder: { options },
            access: access.inheritingCurrentAccess(), log: log
        )
    }

    package func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        streamingSession?.append(buffer)
    }

    package func finishListening(audioURL: URL?, language: String?) async throws -> String {
        defer { streamingSession = nil }
        if let streamingSession {
            let outcome = await streamingSession.finishLivePreview()
            return try await StreamingTranscriptResolver.resolveFinalTranscript(
                engineName: "WhisperEngine",
                audioURL: audioURL,
                livePreviewText: outcome.livePreviewText,
                metrics: outcome.metrics,
                unitLabel: "samples", log: log
            ) { [weak self] in
                guard let self else { return "" }
                return try await self.transcribe(audioURL: audioURL, language: language)
            }
        }
        return try await transcribe(audioURL: audioURL, language: language)
    }

    package func cancelListening() {
        if let streamingSession { retiredStreams.append(streamingSession) }
        streamingSession?.cancel()
        streamingSession = nil
    }

    package func transcribe(audioURL: URL?, language: String?) async throws -> String {
        try await access.withAccess { try await self.transcribeFile(audioURL: audioURL, language: language) }
    }

    private func transcribeFile(audioURL: URL?, language: String?) async throws -> String {
        try Task.checkCancellation()
        guard !closed else { throw ProviderCatalogError.closed }
        guard let whisperKit, isReady else {
            throw UtterContracts.WhisperError.modelNotLoaded(loadError ?? "未知原因")
        }
        guard let url = audioURL else {
            throw UtterContracts.WhisperError.noAudioFile
        }

        let options = decodingOptions(language: language)
        let t0 = CFAbsoluteTimeGetCurrent()

        let results = try await whisperKit.transcribe(
            audioPath: url.path,
            decodeOptions: options
        )
        let text = TranscriptSegmentJoiner.joined(
            results.compactMap { $0.text },
            language: language
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        log.info("[WhisperEngine] transcribed \(text.count) chars in \(String(format: "%.1f", elapsed))s")
        return text
    }

    package func shutdown() async {
        closed = true
        await drainRecognition()
        try? await access.withAccess { self.unload() }
    }

    package func drainRecognition() async {
        cancelListening()
        let streams = retiredStreams
        retiredStreams.removeAll()
        for stream in streams { await stream.shutdown() }
    }

    package func unload() {
        cancelListening()
        whisperKit = nil
        isReady = false
        isLoading = false
        loadError = nil
    }

    private func decodingOptions(
        language: String?,
        temperatureFallbackCount: Int = 5
    ) -> DecodingOptions {
        let promptTokens = recognitionPromptTokens(for: language)
        return DecodingOptions(
            language: language,
            temperatureFallbackCount: temperatureFallbackCount,
            usePrefillPrompt: language != nil || promptTokens != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens,
            suppressBlank: true,
            chunkingStrategy: .vad
        )
    }

    private func recognitionPromptTokens(for language: String?) -> [Int]? {
        guard let tokenizer = whisperKit?.tokenizer else { return nil }
        let context = recognitionContextSnapshot()
        return context.whisperPromptTokens(
            language: language,
            maximumCount: 160
        ) {
            tokenizer.encode(text: $0)
        }
    }

    private func recognitionContextSnapshot() -> SpeechRecognitionContext {
        recognitionContextLock.lock()
        defer { recognitionContextLock.unlock() }
        return recognitionContext
    }

    func dp(_ fraction: Double, stage: SpeechModelProgress.Stage) -> SpeechModelProgress {
        SpeechModelProgress(
            fraction: fraction,
            completedBytes: 0,
            totalBytes: 0,
            speedBytesPerSec: 0,
            elapsedSeconds: 0,
            downloadFraction: fraction,
            stage: stage
        )
    }
}
