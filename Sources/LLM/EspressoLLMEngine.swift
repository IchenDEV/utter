import ANELMRuntime
import Foundation
import Tokenizers

private final class ANELMGenerationContext {
    var tokens: [Int32] = []
}

private func aneLMTokenCallback(_ token: Int32, _ context: UnsafeMutableRawPointer?) -> Int32 {
    let isCancelled = withUnsafeCurrentTask { $0?.isCancelled ?? false }
    guard !isCancelled, let context else { return 0 }
    if token >= 0 {
        Unmanaged<ANELMGenerationContext>.fromOpaque(context).takeUnretainedValue().tokens.append(token)
    }
    return 1
}

actor EspressoLLMEngine {
    static let maximumContextTokens = 2_048

    private final class LoadedModel {
        let path: String
        let runtime: OpaquePointer
        let tokenizer: any Tokenizers.Tokenizer
        let samplerVocabularySize: Int

        init(
            path: String,
            runtime: OpaquePointer,
            tokenizer: any Tokenizers.Tokenizer,
            samplerVocabularySize: Int
        ) {
            self.path = path
            self.runtime = runtime
            self.tokenizer = tokenizer
            self.samplerVocabularySize = samplerVocabularySize
        }

        deinit {
            ane_lm_destroy(runtime)
        }
    }

    private var model: LoadedModel?
    private var lastFailureMessage: String?

    func loadModel(path: String) async throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
        lastFailureMessage = nil
        guard model?.path != url.path else { return }

        Log.info("[ANELMEngine] loading Qwen3 model: \(url.lastPathComponent)")
        do {
            let validated = try await Self.makeValidatedTokenizer(at: url)
            model = nil
            var nativeError: UnsafeMutablePointer<CChar>?
            let runtime = url.path.withCString { ane_lm_create($0, &nativeError) }
            guard let runtime else {
                throw ANELMNativeError(Self.consumeNativeError(&nativeError))
            }
            guard !Task.isCancelled else {
                ane_lm_destroy(runtime)
                throw CancellationError()
            }
            model = LoadedModel(
                path: url.path,
                runtime: runtime,
                tokenizer: validated.tokenizer,
                samplerVocabularySize: validated.samplerVocabularySize
            )
            Log.info("[ANELMEngine] Qwen3 model ready for ANE inference")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw recordFailure(error)
        }
    }

    func generate(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) throws -> String {
        guard let model else { throw EspressoLLMError.modelNotLoaded }
        lastFailureMessage = nil

        let input = Self.formatPrompt(user: prompt, system: systemPrompt, modelName: "Qwen3")
        let promptTokens = model.tokenizer
            .encode(text: input, addSpecialTokens: false)
            .map { Int32(clamping: $0) }
        guard !promptTokens.isEmpty else { throw EspressoLLMError.runtimeFailure }

        let nativeMaxTokens = max(1, maxTokens)
        guard Self.requestFitsContextWindow(
            promptTokenCount: promptTokens.count,
            maxTokens: nativeMaxTokens
        ) else {
            let requiredCacheSlots = promptTokens.count + max(0, nativeMaxTokens - 1)
            throw recordFailure(ANELMNativeError(
                "ANE-LM request needs \(requiredCacheSlots) KV-cache slots; "
                    + "the packaged runtime supports \(Self.maximumContextTokens)"
            ))
        }

        let context = ANELMGenerationContext()
        context.tokens.reserveCapacity(max(0, maxTokens))
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        let eosToken = Int32(clamping: model.tokenizer.eosTokenId ?? -1)
        let stopToken = Int32(clamping: model.tokenizer.convertTokenToId("<|im_end|>") ?? -1)
        var nativeError: UnsafeMutablePointer<CChar>?
        let started = CFAbsoluteTimeGetCurrent()

        let status = promptTokens.withUnsafeBufferPointer { tokens in
            ane_lm_generate(
                model.runtime,
                tokens.baseAddress,
                tokens.count,
                Int32(clamping: nativeMaxTokens),
                Float(temperature),
                1.2,
                Int32(clamping: model.samplerVocabularySize),
                eosToken,
                stopToken,
                aneLMTokenCallback,
                contextPointer,
                &nativeError
            )
        }

        if status == ANE_LM_STATUS_CANCELLED {
            throw CancellationError()
        }
        guard status == ANE_LM_STATUS_OK else {
            let error = ANELMNativeError(Self.consumeNativeError(&nativeError))
            throw recordFailure(error)
        }
        try Task.checkCancellation()

        let output = model.tokenizer.decode(
            tokens: context.tokens.map(Int.init),
            skipSpecialTokens: true
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        let speed = elapsed > 0 ? Double(context.tokens.count) / elapsed : 0
        Log.info(
            "[ANELMEngine] generated \(context.tokens.count) tokens on ANE in "
                + "\(String(format: "%.1f", elapsed))s (\(String(format: "%.1f", speed)) tok/s)"
        )
        return output
    }

    var isLoaded: Bool { model != nil }

    func unload() {
        model = nil
        lastFailureMessage = nil
    }

    func consumeLastFailureMessage() -> String? {
        defer { lastFailureMessage = nil }
        return lastFailureMessage
    }

    static func validateModelDirectory(at url: URL) async throws {
        _ = try await makeValidatedTokenizer(at: url)
    }

    static func requestFitsContextWindow(
        promptTokenCount: Int,
        maxTokens: Int
    ) -> Bool {
        guard promptTokenCount > 0, maxTokens > 0 else { return false }
        let generatedCacheSlots = max(0, maxTokens - 1)
        guard generatedCacheSlots <= maximumContextTokens else { return false }
        return promptTokenCount <= maximumContextTokens - generatedCacheSlots
    }

    private struct ValidatedTokenizer {
        let tokenizer: any Tokenizers.Tokenizer
        let samplerVocabularySize: Int
    }

    private static func makeValidatedTokenizer(at url: URL) async throws -> ValidatedTokenizer {
        guard ModelStorage.llmRepoIsComplete(at: url) else {
            throw EspressoLLMError.invalidModelDirectory
        }
        let configURL = url.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              config["model_type"] as? String == "qwen3" else {
            throw EspressoLLMError.unsupportedModel
        }
        let textConfig = config["text_config"] as? [String: Any] ?? config
        guard let modelVocabularySize = textConfig["vocab_size"] as? Int,
              modelVocabularySize > 0 else {
            throw EspressoLLMError.invalidModelDirectory
        }
        let tokenizerURL = url.appendingPathComponent("tokenizer.json")
        let tokenizerConfigURL = url.appendingPathComponent("tokenizer_config.json")
        guard let tokenizerData = try? Data(contentsOf: tokenizerURL),
              let tokenizerJSON = try? JSONSerialization.jsonObject(with: tokenizerData) as? [String: Any],
              let tokenizerConfigData = try? Data(contentsOf: tokenizerConfigURL),
              let tokenizerConfig = try? JSONSerialization.jsonObject(
                  with: tokenizerConfigData
              ) as? [String: Any],
              let samplerVocabularySize = ANELMTokenizerValidation.samplerVocabularySize(
                  tokenizer: tokenizerJSON,
                  tokenizerConfig: tokenizerConfig,
                  modelVocabularySize: modelVocabularySize
              ) else {
            throw EspressoLLMError.invalidModelDirectory
        }
        var nativeError: UnsafeMutablePointer<CChar>?
        let status = url.path.withCString { ane_lm_validate_model($0, &nativeError) }
        guard status == ANE_LM_STATUS_OK else {
            let detail = consumeNativeError(&nativeError)
            Log.sensitive("[ANELMEngine] rejected model directory: \(detail)")
            throw EspressoLLMError.invalidModelDirectory
        }
        do {
            let tokenizer = try await AutoTokenizer.from(modelFolder: url)
            return ValidatedTokenizer(
                tokenizer: tokenizer,
                samplerVocabularySize: samplerVocabularySize
            )
        } catch {
            Log.sensitive("[ANELMEngine] rejected tokenizer: \(error.localizedDescription)")
            throw EspressoLLMError.invalidModelDirectory
        }
    }

    static func formatPrompt(user: String, system: String, modelName: String) -> String {
        if modelName.lowercased().contains("qwen") {
            return "<|im_start|>system\n\(system)<|im_end|>\n"
                + "<|im_start|>user\n\(user)<|im_end|>\n"
                + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        }
        return "System:\n\(system)\n\nUser:\n\(user)\n\nAssistant:\n"
    }

    private static func consumeNativeError(_ pointer: inout UnsafeMutablePointer<CChar>?) -> String {
        guard let allocated = pointer else { return "ANE-LM failed without an error message" }
        defer {
            ane_lm_free_string(allocated)
            pointer = nil
        }
        return String(cString: allocated)
    }

    private func recordFailure(_ error: Error) -> EspressoLLMError {
        let mapped = error as? EspressoLLMError ?? .runtimeFailure
        Log.sensitive("[ANELMEngine] runtime detail: \(error.localizedDescription)")
        Log.error("[ANELMEngine] \(mapped.localizedDescription)")
        lastFailureMessage = mapped.localizedDescription
        return mapped
    }
}

private struct ANELMNativeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

enum EspressoLLMError: LocalizedError {
    case modelNotLoaded
    case aneBackendUnavailable
    case invalidModelDirectory
    case unsupportedModel
    case runtimeFailure

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return L("error.espresso_not_loaded")
        case .aneBackendUnavailable: return L("error.espresso_ane_unavailable")
        case .invalidModelDirectory: return L("error.espresso_invalid_model")
        case .unsupportedModel: return L("error.espresso_unsupported_model")
        case .runtimeFailure: return L("error.espresso_runtime_failed")
        }
    }
}
