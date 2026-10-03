import MLX
import UtterMediaContracts
import UtterContracts
import AVFoundation
import Foundation
import MLXAudioCore
import MLXAudioSTT

package final class QwenNativeASREngine: SpeechEngine, @unchecked Sendable {
    private let modelDirectory: URL
    private let tailPaddingFrames: AVAudioFrameCount
    private let runtime: QwenNativeASRRuntime
    private let access: any ModelResourceAccess
    private let log: Log
    private var closed = false
    private let contextLock = NSLock()
    private var recognitionContext = SpeechRecognitionContext.empty

    package init(modelPath: String, modelID: String = QwenASRModel.defaultID, access: any ModelResourceAccess, log: Log) {
        self.access = access
        self.log = log
        runtime = QwenNativeASRRuntime(log: log)
        modelDirectory = URL(fileURLWithPath: modelPath).standardizedFileURL
        tailPaddingFrames = modelID == QwenASRModel.confuciusR2T2ID ? 8_000 : 0
    }

    package var isReady: Bool {
        !closed && Self.modelDirectoryIsReady(modelDirectory)
    }

    package func usesModel(at modelPath: String) -> Bool {
        modelDirectory == URL(fileURLWithPath: modelPath).standardizedFileURL
    }

    package func configureRecognition(context: SpeechRecognitionContext) {
        contextLock.withLock { recognitionContext = context }
    }

    package func prepare() async {
        guard isReady else { return }
        do {
            try await access.withAccess { try await self.runtime.prepare(modelDirectory: self.modelDirectory) }
        } catch {
            log.error("[Qwen3ASRNative] model warm-up failed: \(error.localizedDescription)")
        }
    }

    package func transcribe(audioURL: URL?, language: String?) async throws -> String {
        try await access.withAccess { try await self.transcribeFile(audioURL: audioURL, language: language) }
    }

    private func transcribeFile(audioURL: URL?, language: String?) async throws -> String {
        try Task.checkCancellation()
        guard isReady else { throw QwenNativeASRError.notConfigured }
        guard let audioURL else { throw QwenNativeASRError.noAudioFile }

        let prompt = contextLock.withLock {
            QwenRecognitionPrompt(phrases: recognitionContext.phrases)
        }

        let started = CFAbsoluteTimeGetCurrent()
        let result = try await QwenAudioPreprocessor.withPreparedAudio(
            from: audioURL,
            tailPaddingFrames: tailPaddingFrames, log: log
        ) { preparedURL in
            try await QwenContextRecovery.run(prompt: prompt) { context in
                try await runtime.transcribe(
                    audioURL: preparedURL,
                    modelDirectory: modelDirectory,
                    language: language,
                    context: context
                )
            } text: { $0.text }
        }
        guard let result else { return "" }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        log.info(
            "[Qwen3ASRNative] transcribed \(result.text.count) chars in "
                + "\(String(format: "%.1f", elapsed))s; model \(String(format: "%.1f", result.modelTime))s; "
                + "peak \(String(format: "%.2f", result.peakMemoryGB)) GB"
        )
        return result.text
    }

    package func shutdown() async {
        closed = true
        try? await access.withAccess { await self.runtime.unload() }
    }

    package static func modelDirectoryIsReady(_ directory: URL) -> Bool {
        [
            "config.json",
            "model.safetensors",
            "tokenizer_config.json",
            "vocab.json",
            "merges.txt",
        ].allSatisfy { relativePath in
            let url = directory.appendingPathComponent(relativePath)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0
        }
    }
}

private actor QwenNativeASRRuntime {
    struct Result {
        let text: String
        let modelTime: Double
        let peakMemoryGB: Double
    }

    private let log: Log
    init(log: Log) { self.log = log }
    func unload() { model = nil; loadedDirectory = nil; Memory.clearCache() }

    private var model: Qwen3ASRModel?
    private var loadedDirectory: URL?

    func prepare(modelDirectory: URL) async throws {
        _ = try await loadModel(from: modelDirectory)
    }

    func transcribe(
        audioURL: URL,
        modelDirectory: URL,
        language: String?,
        context: String?
    ) async throws -> Result {
        try Task.checkCancellation()
        let model = try await loadModel(from: modelDirectory)
        let (sampleRate, audio) = try loadAudioArray(
            from: audioURL,
            sampleRate: Int(QwenAudioPreprocessor.sampleRate)
        )
        guard sampleRate == Int(QwenAudioPreprocessor.sampleRate) else {
            throw QwenAudioPreprocessorError.conversionFailed
        }

        let output = model.generate(
            audio: audio,
            context: context ?? "",
            language: language
        )
        try Task.checkCancellation()
        return Result(
            text: output.text,
            modelTime: output.totalTime,
            peakMemoryGB: output.peakMemoryUsage
        )
    }

    private func loadModel(from directory: URL) async throws -> Qwen3ASRModel {
        let standardizedDirectory = directory.standardizedFileURL
        if let model, loadedDirectory == standardizedDirectory {
            return model
        }

        let loaded = try await Qwen3ASRModel.fromModelDirectory(standardizedDirectory)
        try Task.checkCancellation()
        model = loaded
        loadedDirectory = standardizedDirectory
        log.info("[Qwen3ASRNative] loaded existing model from \(standardizedDirectory.path)")
        return loaded
    }
}
