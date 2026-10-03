import Foundation
import UtterContracts
import UtterData
import UtterPresentationContracts

extension AppSettings {
    static let shared = AppSettings(defaults: .standard)

    convenience init(defaults: UserDefaults) {
        self.init(service: SettingsStore(defaults: defaults))
    }
}
