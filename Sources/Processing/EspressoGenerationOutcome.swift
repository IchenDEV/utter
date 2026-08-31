import Foundation

enum EspressoGenerationOutcome: Equatable, Sendable {
    case fallback
    case failed
    case unavailable

    var message: String {
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

actor EspressoGenerationTracker {
    private var outcome: EspressoGenerationOutcome?

    func record(_ newOutcome: EspressoGenerationOutcome) {
        outcome = newOutcome
    }

    func clear() {
        outcome = nil
    }

    func consume() -> EspressoGenerationOutcome? {
        defer { outcome = nil }
        return outcome
    }
}

enum EspressoFallbackPolicy {
    @discardableResult
    static func selectMLXIfNeeded(
        after outcome: EspressoGenerationOutcome?,
        settings: AppSettings,
        expectedEspressoModelPath: String
    ) -> Bool {
        guard outcome == .fallback,
              !settings.useRemoteLLM,
              settings.fallbackToMLXOnEspressoFailure,
              settings.localLLMBackend == .espresso,
              settings.espressoModelPath == expectedEspressoModelPath else {
            return false
        }
        settings.localLLMBackend = .mlx
        return true
    }
}
