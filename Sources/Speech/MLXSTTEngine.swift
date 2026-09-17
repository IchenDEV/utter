import Foundation
import MLXAudioCore
import MLXAudioSTT

/// Generic speech engine backed by any mlx-audio-swift STT model.
/// Supports Qwen3-ASR, FireRedASR2-AED, Mega-ASR, SenseVoice, and others.
final class MLXSTTEngine: SpeechEngine, @unchecked Sendable {
    let modelID: String
    private let runtime = MLXSTTRuntime()

    init(modelID: String) {
        self.modelID = modelID
    }

    var isReady: Bool {
        Self.checkModelReady(modelID)
    }

    private static func checkModelReady(_ id: String) -> Bool {
        guard let dir = ModelStorage.asrRepoDir(id) else { return false }
        let requiredFiles = ModelCatalog.asrRequiredFiles(for: id)
        return requiredFiles.allSatisfy { relativePath in
            let file = dir.appendingPathComponent(relativePath)
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0
        }
    }

    func prepare() async {
        guard isReady else { return }
        do {
            try await runtime.prepare(modelID: modelID)
        } catch {
            Log.error("[MLXSTTEngine] model warm-up failed (\(modelID)): \(error.localizedDescription)")
        }
    }

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard isReady else { throw MLXSTTError.notConfigured }
        guard let audioURL else { throw MLXSTTError.noAudioFile }

        let started = CFAbsoluteTimeGetCurrent()
        let result = try await QwenAudioPreprocessor.withPreparedAudio(from: audioURL) { preparedURL in
            try await runtime.transcribe(
                audioURL: preparedURL,
                modelID: modelID,
                language: language
            )
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info(
            "[MLXSTTEngine] \(modelID) transcribed \(result.text.count) chars in "
                + "\(String(format: "%.1f", elapsed))s; model \(String(format: "%.1f", result.modelTime))s; "
                + "peak \(String(format: "%.2f", result.peakMemoryGB)) GB"
        )
        return result.text
    }
}

enum MLXSTTError: LocalizedError {
    case notConfigured
    case noAudioFile
    case modelDirectoryMissing

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("error.local_asr_not_configured")
        case .noAudioFile: return L("error.no_audio")
        case .modelDirectoryMissing: return "ASR model directory not found"
        }
    }
}

private actor MLXSTTRuntime {
    struct Result {
        let text: String
        let modelTime: Double
        let peakMemoryGB: Double
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

        guard let modelDir = ModelStorage.asrRepoDir(modelID) else {
            throw MLXSTTError.modelDirectoryMissing
        }
        let modelType = Self.detectModelType(from: modelDir, modelID: modelID)
        let loaded = try await Self.loadModelFromDirectory(modelDir, modelType: modelType)
        model = loaded
        loadedModelID = modelID
        Log.info("[MLXSTTRuntime] loaded model: \(modelID) (type: \(modelType))")
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
