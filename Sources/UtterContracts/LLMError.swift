import Foundation

package enum LLMError: LocalizedError {
    case modelNotLoaded
    case modelNotDownloaded

    package var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return L("error.llm_not_loaded")
        case .modelNotDownloaded: return L("error.llm_not_downloaded")
        }
    }
}
