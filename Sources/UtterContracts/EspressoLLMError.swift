import Foundation

package enum EspressoLLMError: LocalizedError {
    case modelNotLoaded
    case aneBackendUnavailable
    case invalidModelDirectory
    case unsupportedModel
    case runtimeFailure

    package var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return L("error.espresso_not_loaded")
        case .aneBackendUnavailable: return L("error.espresso_ane_unavailable")
        case .invalidModelDirectory: return L("error.espresso_invalid_model")
        case .unsupportedModel: return L("error.espresso_unsupported_model")
        case .runtimeFailure: return L("error.espresso_runtime_failed")
        }
    }
}
