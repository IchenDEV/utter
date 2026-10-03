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
