import UtterMediaContracts
import UtterPresentationContracts
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
import UtterContracts
import Testing
@testable import UtterPresentation

@Suite("Model upgrade policy")
struct ModelUpgradeTests {
    @Test("SeedASR 2.0 is the recommended Volcengine model")
    func recommendedVolcModel() {
        #expect(VolcASRModel.recommended == .seedASR2)
        #expect(VolcASRModel.recommended.rawValue == "volc.seedasr.sauc.duration")
    }
}
