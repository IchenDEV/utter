#if os(iOS)
import Foundation
import UtterContracts
import UtterMLX
import UtterProcessing

/// Rewrites a dictation with a text model the user downloaded. The model is loaded when a dictation starts,
/// so it is ready when speaking ends, and released a minute after the last use. Every failure returns nil
/// and the caller keeps the recognized text.
@MainActor
final class LocalPolisher {
    static let timeout: Duration = .seconds(6)
    private static let idleLifetime: Duration = .seconds(60)

    private var service: MLXGenerationService?
    private var files: (any ModelFilesService)?
    private var idle: Task<Void, Never>?

    func configure(files: any ModelFilesService, access: any ModelResourceAccess) {
        self.files = files
        service = MLXGenerationService(files: files, access: access, log: Log(service: MobileDiagnostics()))
    }

    func warmUp(modelID: String) {
        guard let service else { return }
        idle?.cancel()
        let request = TextGenerationRequest(prompt: "", modelID: modelID)
        Task { try? await service.prepare(request) }
        scheduleUnload()
    }

    func polish(_ text: String, language: String, protectedTerms: [String], modelID: String) async -> String? {
        guard let service, !text.isEmpty else { return nil }
        idle?.cancel()
        defer { scheduleUnload() }
        let inputLanguage: InputLanguage = language == "en" ? .english : .chinese
        let request = TextGenerationRequest(
            prompt: PromptCatalog.mobilePolishPrompt(text: text),
            systemPrompt: PromptCatalog.mobilePolishInstructions(inputLanguage: inputLanguage),
            modelID: modelID, maxTokens: min(768, max(128, text.count * 2)), temperature: 0.2)
        let output = await withTaskGroup(of: String?.self) { group -> String? in
            group.addTask { try? await service.generate(request) }
            group.addTask { try? await Task.sleep(for: Self.timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return MobilePolisher.accept(Self.clean(output), source: text, inputLanguage: inputLanguage, protectedTerms: protectedTerms)
    }

    func unload() {
        idle?.cancel(); idle = nil
        guard let service else { return }
        Task { await service.unload() }
    }

    private func scheduleUnload() {
        idle?.cancel()
        idle = Task { [weak self] in
            try? await Task.sleep(for: Self.idleLifetime)
            guard !Task.isCancelled else { return }
            self?.unload()
        }
    }

    /// Small models sometimes wrap the answer in quotes or leave a reasoning block in front of it.
    static func clean(_ output: String?) -> String? {
        guard var text = output else { return nil }
        if let end = text.range(of: "</think>") { text = String(text[end.upperBound...]) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\"", "\""), ("“", "”"), ("「", "」")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }
}
#endif
