import Foundation
import MLXAudioCore
import MLXAudioSTT

final class QwenNativeASREngine: SpeechEngine, @unchecked Sendable {
    private let modelDirectory: URL
    private let runtime = QwenNativeASRRuntime()

    init(modelPath: String) {
        modelDirectory = URL(fileURLWithPath: modelPath).standardizedFileURL
    }

    var isReady: Bool {
        Self.modelDirectoryIsReady(modelDirectory)
    }

    func usesModel(at modelPath: String) -> Bool {
        modelDirectory == URL(fileURLWithPath: modelPath).standardizedFileURL
    }

    func prepare() async {
        guard isReady else { return }
        do {
            try await runtime.prepare(modelDirectory: modelDirectory)
        } catch {
            Log.error("[Qwen3ASRNative] model warm-up failed: \(error.localizedDescription)")
        }
    }

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard isReady else { throw QwenNativeASRError.notConfigured }
        guard let audioURL else { throw QwenNativeASRError.noAudioFile }

        let started = CFAbsoluteTimeGetCurrent()
        let result = try await QwenAudioPreprocessor.withPreparedAudio(from: audioURL) { preparedURL in
            try await runtime.transcribe(
                audioURL: preparedURL,
                modelDirectory: modelDirectory,
                language: language
            )
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info(
            "[Qwen3ASRNative] transcribed \(result.text.count) chars in "
                + "\(String(format: "%.1f", elapsed))s; model \(String(format: "%.1f", result.modelTime))s; "
                + "peak \(String(format: "%.2f", result.peakMemoryGB)) GB"
        )
        return result.text
    }

    static func modelDirectoryIsReady(_ directory: URL) -> Bool {
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

enum QwenNativeASRError: LocalizedError {
    case notConfigured
    case noAudioFile

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("error.local_asr_not_configured")
        case .noAudioFile: return L("error.no_audio")
        }
    }
}

private actor QwenNativeASRRuntime {
    struct Result {
        let text: String
        let modelTime: Double
        let peakMemoryGB: Double
    }

    private var model: Qwen3ASRModel?
    private var loadedDirectory: URL?

    func prepare(modelDirectory: URL) async throws {
        _ = try await loadModel(from: modelDirectory)
    }

    func transcribe(
        audioURL: URL,
        modelDirectory: URL,
        language: String?
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

        let output = model.generate(audio: audio, language: language)
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
        model = loaded
        loadedDirectory = standardizedDirectory
        Log.info("[Qwen3ASRNative] loaded existing model from \(standardizedDirectory.path)")
        return loaded
    }
}
