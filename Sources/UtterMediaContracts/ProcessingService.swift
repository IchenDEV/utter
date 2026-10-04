import Foundation
import CoreGraphics
import UtterContracts
import UtterRuntime

package struct ProcessingRequest {
    package let mode: TextProcessingMode
    package let text: String
    package let options: TextProcessingOptions
    package let dictionary: PersonalDictionarySnapshot
    package let screenContext: String
    package let screenImage: CGImage?
    package let memoryContext: String
    package let inputContext: InputContext?
    package let formatKind: TextFormatKind?
    package let allowsPreparedFallback: Bool

    package init(
        mode: TextProcessingMode, text: String, options: TextProcessingOptions,
        dictionary: PersonalDictionarySnapshot, screenContext: String = "",
        screenImage: CGImage? = nil, memoryContext: String = "", inputContext: InputContext? = nil,
        formatKind: TextFormatKind? = nil, allowsPreparedFallback: Bool = false
    ) {
        self.mode = mode
        self.text = text
        self.options = options
        self.dictionary = dictionary
        self.screenContext = screenContext
        self.screenImage = screenImage
        self.memoryContext = memoryContext
        self.inputContext = inputContext
        self.formatKind = formatKind
        self.allowsPreparedFallback = allowsPreparedFallback
    }

    package func withMode(_ mode: TextProcessingMode) -> ProcessingRequest {
        ProcessingRequest(mode: mode, text: text, options: options, dictionary: dictionary,
            screenContext: screenContext, screenImage: screenImage, memoryContext: memoryContext,
            inputContext: inputContext, formatKind: formatKind, allowsPreparedFallback: allowsPreparedFallback)
    }
}

package struct ProcessingResult: Sendable {
    package let text: String
    package let generationOutcome: EspressoGenerationOutcome?

    package init(text: String, generationOutcome: EspressoGenerationOutcome? = nil) {
        self.text = text
        self.generationOutcome = generationOutcome
    }
}

@MainActor
package protocol ProcessingService: AnyObject {
    func cleanReplacement(_ text: String, language: InputLanguage) throws -> String
    func process(_ request: ProcessingRequest) async throws -> ProcessingResult
    func resolveEditCommand(
        text: String, options: TextProcessingOptions, dictionary: PersonalDictionarySnapshot,
        context: SpokenEditCommandResolutionContext
    ) async throws -> SpokenEditCommandLLMResolution?
}

extension ProcessingService {
    package func cleanReplacement(_ text: String, language: InputLanguage) throws -> String {
        SpokenEditCommandPayloadCleaner.cleanReplacement(text)
    }
}

package enum ProcessingError: LocalizedError {
    case emptyResult(EspressoGenerationOutcome?)
    package var errorDescription: String? {
        switch self {
        case .emptyResult(let outcome): return outcome?.message ?? L("pipeline.formatting_failed")
        }
    }
}

extension ProcessingServices {
    package static let text = ServiceKey<any ProcessingService>("processing.text")
}
