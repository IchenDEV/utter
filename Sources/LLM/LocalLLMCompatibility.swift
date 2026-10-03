import Foundation
import UtterContracts
import UtterMLX
import UtterANE

extension LLMEngine {
    init() { self.init(files: LiveModelFiles(), log: UtterContracts.Log(service: Log.service)) }
}

extension VLMEngine {
    init() { self.init(files: LiveModelFiles(), log: UtterContracts.Log(service: Log.service)) }
}

extension EspressoLLMEngine {
    init() { self.init(files: LiveModelFiles(), log: UtterContracts.Log(service: Log.service)) }
    static func validateModelDirectory(at url: URL) async throws {
        try await validateModelDirectory(at: url, files: LiveModelFiles(), log: UtterContracts.Log(service: Log.service))
    }
}
