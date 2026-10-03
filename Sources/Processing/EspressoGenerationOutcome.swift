import UtterPresentationContracts
import UtterContracts
import Foundation

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
