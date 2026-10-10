import UtterMediaContracts
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterPresentationContracts
import Foundation
import UtterContracts
import UtterData
import UtterSession

extension IntegrationClientRegistry {
    convenience init(defaults: UserDefaults = .standard, key: String = "integrationApprovedClients") {
        self.init(defaults: defaults, key: key, reportError: TestDiagnostics.error)
    }
}

extension IntegrationServiceSettings {
    @MainActor
    static var live: IntegrationServiceSettings {
        IntegrationServiceSettings(
            developerInterfaceEnabled: AppSettings.shared.developerInterfaceEnabled,
            httpToken: AppSettings.shared.developerHTTPToken
        )
    }
}

@MainActor
extension OpenTypeService {
    convenience init(registry: any IntegrationClientStore) {
        self.init(settingsProvider: { .live }, registry: registry)
    }
}
