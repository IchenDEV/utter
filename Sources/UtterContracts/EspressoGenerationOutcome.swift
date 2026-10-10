import Foundation

package enum EspressoGenerationOutcome: Equatable, Sendable {
    case fallback
    case failed
    case unavailable

    package var message: String {
        switch self {
        case .fallback:
            return L("status.espresso_fell_back_to_mlx")
        case .failed:
            return L("error.espresso_runtime_failed")
        case .unavailable:
            return L("error.espresso_mlx_fallback_unavailable")
        }
    }
}

