import Foundation
import UtterContracts

extension TextProcessor {
    package func benchmarkLLM(modelID: String) async throws -> ModelBenchmarkResult {
        var values = snapshotSettings()
        values.useRemoteLLM = false
        values.localLLMBackend = .mlx
        values.llmModel = modelID
        let options = TextProcessingOptions(settings: values).freezingModelLocations(using: modelFiles)
        let dictionary = snapshotDictionary()
        let chinese = [.auto, .chinese, .cantonese].contains(options.inputLanguage)
        let short = chinese ? "周五下午三点开会，请确认预算。" : "Meet on Friday at three and confirm the budget."
        let paragraph = chinese
            ? "今天定了三件事：第一项是梳理方案，第二项是确认时间，第三项是检查预算。Redis 已部署，Kubernetes 还需核对配置。"
            : "Today we agreed on three tasks: review the proposal, confirm the schedule, and check the budget. Redis is deployed; Kubernetes configuration still needs review."
        let workloads = [("short", short), ("medium", paragraph), ("long", Array(repeating: paragraph, count: 6).joined(separator: " "))]
            .map { length, source in
                let text = prepareForFormatting(text: source, inputLanguage: options.inputLanguage, dictionarySnapshot: dictionary)
                let assembly = formattingAssembly(options: options, screenContext: "", screenImageAvailable: false,
                    memoryContext: "", inputContext: nil, formatKind: TextFormatClassifier.classify(text: text, context: nil).kind,
                    dictionarySnapshot: dictionary, transcript: text)
                let parameters = formattingOptions(for: text, style: options.languageStyle)
                let request = generationRequest(prompt: assembly.userPrompt(containing: formattingUserPrompt(text: text, options: options)),
                    systemPrompt: assembly.stablePrefix, options: options, maxTokens: parameters.maxTokens, temperature: parameters.temperature)
                return (length: length, request: request)
            }
        return try await withLocalModelAccess {
            let provider = try await self.providers.create(id: "generation.mlx", request: .benchmark)
            return try await ModelBenchmarkSuite.run(workloads: workloads, provider: provider)
        }
    }
}
