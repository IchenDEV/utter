import Foundation
import UtterContracts

package final class SettingsCredentialsService: CredentialsService {
    private let settings: any SettingsService

    package init(settings: any SettingsService) { self.settings = settings }
    package var snapshot: CredentialsSnapshot { CredentialsSnapshot(settings: settings.values) }

    package func update(_ mutation: (inout CredentialsSnapshot) -> Void) {
        settings.update { values in
            var credentials = CredentialsSnapshot(settings: values)
            mutation(&credentials)
            values = credentials.applying(to: values)
        }
    }

    package func resetDeveloperHTTPToken() { settings.resetDeveloperHTTPToken() }
    package func observe(_ callback: @escaping (CredentialsSnapshot) -> Void) -> UUID {
        settings.observe { callback(CredentialsSnapshot(settings: $0)) }
    }
    package func removeObserver(_ id: UUID) { settings.removeObserver(id) }
}
