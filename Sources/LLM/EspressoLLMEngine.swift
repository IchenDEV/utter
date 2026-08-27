import ESPRuntime
import Foundation
import RealModelInference

actor EspressoLLMEngine {
    private final class LoadedModel {
        let path: String
        let name: String
        var engine: RealModelInferenceEngine

        init(path: String, name: String, engine: consuming RealModelInferenceEngine) {
            self.path = path
            self.name = name
            self.engine = engine
        }
    }

    private var model: LoadedModel?

    func loadModel(path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
        guard model?.path != url.path else { return }

        Log.info("[EspressoLLMEngine] loading bundle: \(url.path)")
        let bundle = try ESPRuntimeBundle.open(at: url)
        let selection = try ESPRuntimeRunner.resolve(bundle: bundle)
        guard selection.backend == .anePrivate else {
            throw EspressoLLMError.aneBackendUnavailable
        }

        let engine = try RealModelInferenceEngine.build(
            config: bundle.config,
            weightDir: bundle.archive.weightsURL.path,
            tokenizerDir: bundle.archive.tokenizerURL.path
        )
        model = LoadedModel(path: url.path, name: bundle.config.name, engine: engine)
        Log.info("[EspressoLLMEngine] bundle ready for ANE inference")
    }

    func generate(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) throws -> String {
        guard let model else { throw EspressoLLMError.modelNotLoaded }
        let input = Self.formatPrompt(
            user: prompt,
            system: systemPrompt,
            modelName: model.name
        )
        let started = CFAbsoluteTimeGetCurrent()
        let result = try model.engine.generate(
            prompt: input,
            maxTokens: maxTokens,
            temperature: Float(temperature)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info(
            "[EspressoLLMEngine] generated \(result.text.count) chars on ANE in "
                + "\(String(format: "%.1f", elapsed))s (\(String(format: "%.1f", result.tokensPerSecond)) tok/s)"
        )
        return result.text
    }

    var isLoaded: Bool { model != nil }

    func unload() {
        model = nil
    }

    static func formatPrompt(user: String, system: String, modelName: String) -> String {
        if modelName.lowercased().contains("qwen") {
            return "<|im_start|>system\n\(system)<|im_end|>\n"
                + "<|im_start|>user\n\(user)<|im_end|>\n"
                + "<|im_start|>assistant\n"
        }
        return "System:\n\(system)\n\nUser:\n\(user)\n\nAssistant:\n"
    }
}

enum EspressoLLMError: LocalizedError {
    case modelNotLoaded
    case aneBackendUnavailable

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return L("error.espresso_not_loaded")
        case .aneBackendUnavailable: return L("error.espresso_ane_unavailable")
        }
    }
}
