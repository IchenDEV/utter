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
import UtterRemoteInference
import UtterIngress
import Foundation
import UtterContracts
import UtterMLX
import UtterANE

extension LLMEngine {
    init() { self.init(files: LiveModelFiles(), log: UtterContracts.Log(service: TestDiagnostics.service)) }
}

extension VLMEngine {
    init() { self.init(files: LiveModelFiles(), log: UtterContracts.Log(service: TestDiagnostics.service)) }
}

extension EspressoLLMEngine {
    init() { self.init(files: LiveModelFiles(), log: UtterContracts.Log(service: TestDiagnostics.service)) }
    static func validateModelDirectory(at url: URL) async throws {
        try await validateModelDirectory(at: url, files: LiveModelFiles(), log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}
