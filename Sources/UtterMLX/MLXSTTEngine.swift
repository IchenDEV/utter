import MLX
import UtterMediaContracts
import UtterContracts
import Foundation
import MLXAudioCore
import MLXAudioSTT

/// Generic speech engine backed by any mlx-audio-swift STT model.
/// Supports Qwen3-ASR, FireRedASR2-AED, Mega-ASR, SenseVoice, and others.
package final class MLXSTTEngine: SpeechEngine, @unchecked Sendable {
    let modelID: String
    private let runtime: MLXSTTRuntime
    private let files: any ModelFilesService
    private let access: any ModelResourceAccess
    private let log: Log
    private var closed = false

    package init(modelID: String, files: any ModelFilesService, access: any ModelResourceAccess, log: Log) {
        self.files = files
        self.access = access
        self.log = log
        runtime = MLXSTTRuntime(files: files, log: log)
        self.modelID = modelID
    }

    package var isReady: Bool {
        !closed && checkModelReady(modelID)
    }

    private func checkModelReady(_ id: String) -> Bool {
        guard let dir = files.installedSpeechModelURL(id) else { return false }
        let requiredFiles = files.speechRequiredFiles(id)
        return requiredFiles.allSatisfy { relativePath in
            let file = dir.appendingPathComponent(relativePath)
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0
        }
    }

    package func prepare() async {
        guard isReady else { return }
        do {
            try await access.withAccess { try await self.runtime.prepare(modelID: self.modelID) }
        } catch {
            log.error("[MLXSTTEngine] model warm-up failed (\(modelID)): \(error.localizedDescription)")
        }
    }

    package func transcribe(audioURL: URL?, language: String?) async throws -> String {
        try await access.withAccess { try await self.transcribeFile(audioURL: audioURL, language: language) }
    }

    private func transcribeFile(audioURL: URL?, language: String?) async throws -> String {
        try Task.checkCancellation()
        guard isReady else { throw MLXSTTError.notConfigured }
        guard let audioURL else { throw MLXSTTError.noAudioFile }

        let started = CFAbsoluteTimeGetCurrent()
        let result = try await QwenAudioPreprocessor.withPreparedAudio(from: audioURL, log: log) { preparedURL in
            try await runtime.transcribe(
                audioURL: preparedURL,
                modelID: modelID,
                language: language
            )
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        log.info(
            "[MLXSTTEngine] \(modelID) transcribed \(result.text.count) chars in "
                + "\(String(format: "%.1f", elapsed))s; model \(String(format: "%.1f", result.modelTime))s; "
                + "peak \(String(format: "%.2f", result.peakMemoryGB)) GB"
        )
        return result.text
    }
    package func shutdown() async {
        closed = true
        try? await access.withAccess { await self.runtime.unload() }
    }

}

private actor MLXSTTRuntime {
    struct Result {
        let text: String
        let modelTime: Double
        let peakMemoryGB: Double
    }

    private let files: any ModelFilesService
    private let log: Log
    init(files: any ModelFilesService, log: Log) { self.files = files; self.log = log }
    private var modelLoadAttempted = false

    func unload() {
        model = nil
        loadedModelID = nil
        if modelLoadAttempted {
            modelLoadAttempted = false
            Memory.clearCache()
        }
    }

    private var model: (any STTGenerationModel)?
    private var loadedModelID: String?

    func prepare(modelID: String) async throws {
        _ = try await loadModel(modelID: modelID)
    }

    func transcribe(
        audioURL: URL,
        modelID: String,
        language: String?
    ) async throws -> Result {
        try Task.checkCancellation()
        let model = try await loadModel(modelID: modelID)
        let (sampleRate, audio) = try loadAudioArray(
            from: audioURL,
            sampleRate: Int(QwenAudioPreprocessor.sampleRate)
        )
        guard sampleRate == Int(QwenAudioPreprocessor.sampleRate) else {
            throw QwenAudioPreprocessorError.conversionFailed
        }

        let defaults = model.defaultGenerationParameters
        let finalParams = STTGenerateParameters(
            maxTokens: defaults.maxTokens,
            temperature: defaults.temperature,
            topP: defaults.topP,
            topK: defaults.topK,
            verbose: defaults.verbose,
            language: language,
            chunkDuration: defaults.chunkDuration,
            minChunkDuration: defaults.minChunkDuration,
            repetitionPenalty: defaults.repetitionPenalty,
            repetitionContextSize: defaults.repetitionContextSize
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        let output = model.generate(audio: audio, generationParameters: finalParams)
        let modelTime = CFAbsoluteTimeGetCurrent() - startTime
        try Task.checkCancellation()

        return Result(
            text: output.text,
            modelTime: modelTime,
            peakMemoryGB: output.peakMemoryUsage
        )
    }

    private func loadModel(modelID: String) async throws -> any STTGenerationModel {
        if let model, loadedModelID == modelID {
            return model
        }

        guard let modelDir = files.installedSpeechModelURL(modelID) else {
            throw MLXSTTError.modelDirectoryMissing
        }
        let modelType = Self.detectModelType(from: modelDir, modelID: modelID)
        modelLoadAttempted = true
        let loaded = try await Self.loadModelFromDirectory(modelDir, modelType: modelType)
        try Task.checkCancellation()
        model = loaded
        loadedModelID = modelID
        log.info("[MLXSTTRuntime] loaded model: \(modelID) (type: \(modelType))")
        return loaded
    }

    private static func detectModelType(from dir: URL, modelID: String) -> String {
        let configURL = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["model_type"] as? String {
            return type.lowercased()
        }
        let lower = modelID.lowercased()
        if lower.contains("firered") { return "fireredasr2" }
        if lower.contains("sensevoice") { return "sensevoice" }
        if lower.contains("mega-asr") || lower.contains("qwen3-asr") { return "qwen3_asr" }
        return "qwen3_asr"
    }

    private static func loadModelFromDirectory(
        _ dir: URL,
        modelType: String
    ) async throws -> any STTGenerationModel {
        switch modelType {
        case "fireredasr2", "firered", "fire_red":
            return try FireRedASR2Model.fromDirectory(dir)
        case "qwen3_asr", "qwen3-asr":
            return try await Qwen3ASRModel.fromModelDirectory(dir)
        default:
            return try await Qwen3ASRModel.fromModelDirectory(dir)
        }
    }
}
