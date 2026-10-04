import UtterMediaContracts
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
import Foundation
import UtterContracts
import UtterData
import UtterPresentationContracts

extension AppSettings {
    static let shared = AppSettings(defaults: .standard)

    convenience init(defaults: UserDefaults) {
        let store = SettingsStore(defaults: defaults)
        self.init(service: store, credentials: SettingsCredentialsService(settings: store))
    }
}
