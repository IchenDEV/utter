import MLX
import UtterMediaContracts
import UtterContracts
import AVFoundation
import Foundation
import MLXAudioCore

package final class Audio8NativeASREngine: SpeechEngine, @unchecked Sendable {
    private let modelDirectory: URL
    private let runtime: Audio8ASRRuntime
    private let access: any ModelResourceAccess
    private let log: Log
    private var closed = false
    private let contextLock = NSLock()
    private var recognitionContext = SpeechRecognitionContext.empty

    package init(modelPath: String, access: any ModelResourceAccess, log: Log) {
        self.access = access
        self.log = log
        runtime = Audio8ASRRuntime(log: log)
        modelDirectory = URL(fileURLWithPath: modelPath).standardizedFileURL
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
            log.error("[Audio8ASR] model warm-up failed: \(error.localizedDescription)")
        }
    }

    package func transcribe(audioURL: URL?, language: String?) async throws -> String {
        try await access.withAccess { try await self.transcribeFile(audioURL: audioURL) }
    }

    private func transcribeFile(audioURL: URL?) async throws -> String {
        try Task.checkCancellation()
        guard isReady else { throw Audio8ASRError.notConfigured }
        guard let audioURL else { throw Audio8ASRError.noAudioInput }
        let hotwords = contextLock.withLock {
            QwenRecognitionPrompt(phrases: recognitionContext.phrases).phrases
        }

        let started = CFAbsoluteTimeGetCurrent()
        let result = try await QwenAudioPreprocessor.withPreparedAudio(
            from: audioURL,
            tailPaddingFrames: 0,
            log: log
        ) { preparedURL in
            try await runtime.transcribe(
                audioURL: preparedURL,
                modelDirectory: modelDirectory,
                hotwords: hotwords
            )
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        log.info(
            "[Audio8ASR] transcribed \(result.text.count) chars in "
                + "\(String(format: "%.1f", elapsed))s; model \(String(format: "%.1f", result.modelTime))s; "
                + "peak \(String(format: "%.2f", result.peakMemoryGB)) GB"
        )
        guard !result.text.isEmpty else { throw Audio8ASRError.emptyRecognitionResult }
        return result.text
    }

    package func shutdown() async {
        closed = true
        try? await access.withAccess { await self.runtime.unload() }
    }

    package static func modelDirectoryIsReady(_ directory: URL) -> Bool {
        Audio8ASRModel.requiredFiles.allSatisfy { relativePath in
            let url = directory.appendingPathComponent(relativePath)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0
        }
    }
}

private actor Audio8ASRRuntime {
    private let log: Log
    private var model: Audio8ASRInferenceModel?
    private var loadedDirectory: URL?
    private var modelLoadAttempted = false

    init(log: Log) { self.log = log }

    func unload() {
        model = nil
        loadedDirectory = nil
        if modelLoadAttempted {
            modelLoadAttempted = false
            Memory.clearCache()
        }
    }

    func prepare(modelDirectory: URL) async throws {
        _ = try await loadModel(from: modelDirectory)
    }

    func transcribe(audioURL: URL, modelDirectory: URL, hotwords: [String]) async throws -> Audio8ASRGenerationResult {
        try Task.checkCancellation()
        let (sampleRate, audio) = try loadAudioArray(from: audioURL, sampleRate: Int(QwenAudioPreprocessor.sampleRate))
        guard sampleRate == Int(QwenAudioPreprocessor.sampleRate) else {
            throw QwenAudioPreprocessorError.conversionFailed
        }
        guard audio.dim(0) <= 30 * Int(QwenAudioPreprocessor.sampleRate) else {
            throw Audio8ASRError.audioTooLong
        }
        let model = try await loadModel(from: modelDirectory)
        let result = try model.generate(audio: audio, hotwords: hotwords, maxTokens: 128)
        try Task.checkCancellation()
        return result
    }

    private func loadModel(from directory: URL) async throws -> Audio8ASRInferenceModel {
        let standardizedDirectory = directory.standardizedFileURL
        if let model, loadedDirectory == standardizedDirectory {
            return model
        }
        modelLoadAttempted = true
        let loaded = try await Audio8ASRInferenceModel.fromModelDirectory(standardizedDirectory)
        try Task.checkCancellation()
        model = loaded
        loadedDirectory = standardizedDirectory
        log.info("[Audio8ASR] loaded existing model from \(standardizedDirectory.path)")
        return loaded
    }
}
