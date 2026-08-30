import Foundation

enum EspressoGenerationOutcome: Equatable, Sendable {
    case fallback
    case unavailable

    var message: String {
        switch self {
        case .fallback:
            return L("status.espresso_fell_back_to_mlx")
        case .unavailable:
            return L("error.espresso_mlx_fallback_unavailable")
        }
    }
}

actor EspressoGenerationTracker {
    private var outcome: EspressoGenerationOutcome?

    func record(_ newOutcome: EspressoGenerationOutcome) {
        if outcome != .unavailable {
            outcome = newOutcome
        }
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
              settings.localLLMBackend == .espresso,
              settings.espressoModelPath == expectedEspressoModelPath else {
            return false
        }
        settings.localLLMBackend = .mlx
        return true
    }
}
