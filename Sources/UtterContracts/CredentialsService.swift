import Foundation

package struct CredentialsSnapshot: Equatable, Sendable {
    package var remoteAPIKey: String
    package var volcAppKey: String
    package var volcAccessKey: String
    package var developerHTTPToken: String

    package init(remoteAPIKey: String = "", volcAppKey: String = "", volcAccessKey: String = "", developerHTTPToken: String = "") {
        self.remoteAPIKey = remoteAPIKey
        self.volcAppKey = volcAppKey
        self.volcAccessKey = volcAccessKey
        self.developerHTTPToken = developerHTTPToken
    }

    package init(settings: SettingsValues) {
        self.init(remoteAPIKey: settings.remoteAPIKey, volcAppKey: settings.volcAppKey, volcAccessKey: settings.volcAccessKey, developerHTTPToken: settings.developerHTTPToken)
    }

    package func applying(to settings: SettingsValues) -> SettingsValues {
        var values = settings
        values.remoteAPIKey = remoteAPIKey
        values.volcAppKey = volcAppKey
        values.volcAccessKey = volcAccessKey
        values.developerHTTPToken = developerHTTPToken
        return values
    }
}

package protocol CredentialsService: AnyObject {
    var snapshot: CredentialsSnapshot { get }
    func update(_ mutation: (inout CredentialsSnapshot) -> Void)
    func resetDeveloperHTTPToken()
    func observe(_ callback: @escaping (CredentialsSnapshot) -> Void) -> UUID
    func removeObserver(_ id: UUID)
}
