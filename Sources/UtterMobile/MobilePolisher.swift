#if os(iOS)
import Foundation
import FoundationModels
import UtterContracts
import UtterProcessing

/// Rewrites a finished dictation with Apple's on-device language model. Nothing leaves the device.
/// Any failure, timeout or unfaithful rewrite returns nil and the caller keeps the original text.
enum MobilePolisher {
    static let timeout: Duration = .seconds(5)

    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    static func polish(_ text: String, language: String, protectedTerms: [String]) async -> String? {
        guard isAvailable, !text.isEmpty else { return nil }
        let inputLanguage: InputLanguage = language == "en" ? .english : .chinese
        let polished = await withTaskGroup(of: String?.self) { group -> String? in
            group.addTask {
                let session = LanguageModelSession(instructions: PromptCatalog.mobilePolishInstructions(inputLanguage: inputLanguage))
                let response = try? await session.respond(to: PromptCatalog.mobilePolishPrompt(text: text))
                return response?.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return accept(polished, source: text, inputLanguage: inputLanguage, protectedTerms: protectedTerms)
    }

    /// A rewrite is used only when it differs from the source and passes the same fidelity check as desktop.
    static func accept(_ polished: String?, source: String, inputLanguage: InputLanguage, protectedTerms: [String]) -> String? {
        guard let polished, !polished.isEmpty, polished != source,
              TranscriptFidelityGuard.violation(source: source, candidate: polished, protectedTerms: protectedTerms,
                                                inputLanguage: inputLanguage, enforceSemanticFidelity: true) == nil
        else { return nil }
        return polished
    }
}
#endif
