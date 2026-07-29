import Foundation
import AVFoundation
import WhisperKit
import CoreML

final class WhisperEngine: SpeechEngine, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private let modelName: String?
    private(set) var isReady = false
    private(set) var isLoading = false
    private var loadError: String?
    private var streamingSession: WhisperStreamingSession?
    private let recognitionContextLock = NSLock()
    private var recognitionContext = SpeechRecognitionContext.empty

    init(modelName: String = "large-v3") {
        self.modelName = modelName.isEmpty ? nil : modelName
    }

    func loadModel(progress: @escaping (DownloadProgress) -> Void) async throws {
        guard !isLoading && !isReady else { return }
        isLoading = true

        do {
            let recommended = WhisperKit.recommendedModels()
            let requestedModel = modelName ?? recommended.default
            var selectedModel = ModelStorage.localWhisperURL(requestedModel) != nil
                ? requestedModel
                : WhisperModelSelection.resolve(
                    requested: requestedModel,
                    available: recommended.supported,
                    fallback: recommended.default
                )
            let localFolder = ModelStorage.localWhisperURL(selectedModel)

            if localFolder == nil, !recommended.supported.contains(selectedModel) {
                Log.info("[WhisperEngine] '\(selectedModel)' is unavailable, fallback: \(recommended.default)")
                selectedModel = recommended.default
            }
            Log.info("[WhisperEngine] using model: \(selectedModel)")

            let folder = localFolder ?? ModelStorage.whisperVariantDir(selectedModel)
            guard ModelStorage.whisperModelIsComplete(at: folder) else {
                isLoading = false
                throw WhisperError.modelNotLoaded(L("model.download_required"))
            }
            Log.info("[WhisperEngine] loading local model assets")

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
                throw WhisperError.compileFailed(error.localizedDescription)
            }

            progress(dp(0.85, stage: .loading))
            do {
                try await kit.loadModels()
            } catch {
                isLoading = false
                throw WhisperError.loadFailed(error.localizedDescription)
            }

            whisperKit = kit
            isReady = true
            isLoading = false
            loadError = nil
            progress(dp(1.0, stage: .done))
            Log.info("[WhisperEngine] model loaded")
        } catch let error as WhisperError {
            loadError = error.localizedDescription
            isReady = false
            Log.error("[WhisperEngine] \(error.localizedDescription)")
            throw error
        } catch {
            loadError = error.localizedDescription
            isReady = false
            isLoading = false
            Log.error("[WhisperEngine] model load failed: \(error.localizedDescription)")
            throw error
        }
    }

    var supportsStreaming: Bool { true }

    func configureRecognition(context: SpeechRecognitionContext) {
        recognitionContextLock.lock()
        defer { recognitionContextLock.unlock() }
        recognitionContext = context
    }

    func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        guard let whisperKit, isReady else { return }
        let options = decodingOptions(
            language: language,
            temperatureFallbackCount: 1
        )
        streamingSession = WhisperStreamingSession(
            whisperKit: whisperKit,
            partialHandler: onPartialResult,
            optionsBuilder: { options }
        )
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        streamingSession?.append(buffer)
    }

    func finishListening(audioURL: URL?, language: String?) async throws -> String {
        defer { streamingSession = nil }
        if let streamingSession {
            let outcome = await streamingSession.finishLivePreview()
            return try await StreamingTranscriptResolver.resolveFinalTranscript(
                engineName: "WhisperEngine",
                audioURL: audioURL,
                livePreviewText: outcome.livePreviewText,
                metrics: outcome.metrics,
                unitLabel: "samples"
            ) { [weak self] in
                guard let self else { return "" }
                return try await self.transcribe(audioURL: audioURL, language: language)
            }
        }
        return try await transcribe(audioURL: audioURL, language: language)
    }

    func cancelListening() {
        streamingSession?.cancel()
        streamingSession = nil
    }

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard let whisperKit, isReady else {
            throw WhisperError.modelNotLoaded(loadError ?? "未知原因")
        }
        guard let url = audioURL else {
            throw WhisperError.noAudioFile
        }

        let options = decodingOptions(language: language)
        let t0 = CFAbsoluteTimeGetCurrent()

        let results = try await whisperKit.transcribe(
            audioPath: url.path,
            decodeOptions: options
        )
        let text = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[WhisperEngine] transcribed \(text.count) chars in \(String(format: "%.1f", elapsed))s")
        return text
    }

    func unload() {
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

    private func dp(_ fraction: Double, stage: DownloadProgress.Stage) -> DownloadProgress {
        DownloadProgress(
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
