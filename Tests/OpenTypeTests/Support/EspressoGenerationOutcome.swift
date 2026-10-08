import UtterMediaContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
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
