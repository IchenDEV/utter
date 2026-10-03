import UtterMediaContracts
import UtterContracts
import Foundation
import AVFoundation
import WhisperKit
import CoreML

package final class WhisperEngine: SpeechEngine, @unchecked Sendable {
    private let files: any ModelFilesService
    private let access: any ModelResourceAccess
    private let log: Log
    private var closed = false
    private var whisperKit: WhisperKit?
    private let modelName: String?
    package private(set) var isReady = false
    package private(set) var isLoading = false
    private var loadError: String?
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

    package func loadModel(progress: @escaping (SpeechModelProgress) -> Void) async throws {
        try await access.withAccess { try await self.loadLocalModel(progress: progress) }
    }

    private func loadLocalModel(progress: @escaping (SpeechModelProgress) -> Void) async throws {
        try Task.checkCancellation()
        guard !closed else { throw ProviderCatalogError.closed }
        guard !isLoading && !isReady else { return }
        isLoading = true

        do {
            let recommended = WhisperKit.recommendedModels()
            let requestedModel = modelName ?? recommended.default
            var selectedModel = files.installedWhisperURL(requestedModel) != nil
                ? requestedModel
                : WhisperModelSelection.resolve(
                    requested: requestedModel,
                    available: recommended.supported,
                    fallback: recommended.default
                )
            let localFolder = files.installedWhisperURL(selectedModel)

            if localFolder == nil, !recommended.supported.contains(selectedModel) {
                log.info("[WhisperEngine] '\(selectedModel)' is unavailable, fallback: \(recommended.default)")
                selectedModel = recommended.default
            }
            log.info("[WhisperEngine] using model: \(selectedModel)")

            let folder = localFolder ?? files.whisperVariantURL(selectedModel)
            guard files.whisperModelIsComplete(at: folder) else {
                isLoading = false
                throw UtterContracts.WhisperError.modelNotLoaded(L("model.download_required"))
            }
            log.info("[WhisperEngine] loading local model assets")

            progress(dp(0.62, stage: .compiling))

            let compute = ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )

            let kit: WhisperKit
            do {
                kit = try await WhisperKit(
                    WhisperKitConfig(
                        modelFolder: folder.path,
                        computeOptions: compute,
                        verbose: false,
                        prewarm: false,
                        load: false
                    )
                )

                progress(dp(0.70, stage: .compiling))
                try await kit.prewarmModels()
            } catch {
                isLoading = false
                throw UtterContracts.WhisperError.compileFailed(error.localizedDescription)
            }

            progress(dp(0.85, stage: .loading))
            do {
                try await kit.loadModels()
            } catch {
                isLoading = false
                throw UtterContracts.WhisperError.loadFailed(error.localizedDescription)
            }

            try Task.checkCancellation()
            guard !closed else { throw ProviderCatalogError.closed }
            whisperKit = kit
            isReady = true
            isLoading = false
            loadError = nil
            progress(dp(1.0, stage: .done))
            log.info("[WhisperEngine] model loaded")
        } catch let error as UtterContracts.WhisperError {
            loadError = error.localizedDescription
            isReady = false
            log.error("[WhisperEngine] \(error.localizedDescription)")
            throw error
        } catch {
            loadError = error.localizedDescription
            isReady = false
            isLoading = false
            log.error("[WhisperEngine] model load failed: \(error.localizedDescription)")
            throw error
        }
    }

    package func prepare() async {
        let retired = retiredStreams
        retiredStreams.removeAll()
        for stream in retired { await stream.shutdown() }
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
            access: access, log: log
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
        await streamingSession?.shutdown()
        for stream in retiredStreams { await stream.shutdown() }
        retiredStreams.removeAll()
        try? await access.withAccess { self.unload() }
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

    private func dp(_ fraction: Double, stage: SpeechModelProgress.Stage) -> SpeechModelProgress {
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
