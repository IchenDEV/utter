import Foundation
import XCTest
import UtterContracts
@testable import UtterData

final class CredentialsServiceTests: XCTestCase {
    func testCredentialChangesPreserveLegacyKeysAndOneStore() throws {
        let suite = "utter.credentials.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let credentials = SettingsCredentialsService(settings: settings)
        credentials.update {
            $0.remoteAPIKey = "fixture-remote"
            $0.volcAppKey = "fixture-app"
            $0.volcAccessKey = "fixture-access"
        }
        let reopened = SettingsCredentialsService(settings: SettingsStore(defaults: defaults))
        XCTAssertEqual(reopened.snapshot, credentials.snapshot)
        XCTAssertEqual(settings.values.remoteAPIKey, credentials.snapshot.remoteAPIKey)
        settings.update { $0.remoteAPIKey = "changed-through-legacy-key" }
        XCTAssertEqual(credentials.snapshot.remoteAPIKey, "changed-through-legacy-key")
    }

    func testFrozenCredentialsCanReplaceLegacyValuesWithoutChangingPreferences() throws {
        var settings = SettingsValues()
        settings.remoteAPIKey = "legacy-token"
        settings.llmModel = "selected-model"
        let frozen = CredentialsSnapshot(remoteAPIKey: "replacement-token")
        let session = frozen.applying(to: settings)
        settings.remoteAPIKey = "later-token"
        XCTAssertEqual(session.remoteAPIKey, "replacement-token")
        XCTAssertEqual(session.llmModel, "selected-model")
        XCTAssertEqual(frozen.remoteAPIKey, "replacement-token")
    }

    func testResetTokenAndObservationUseAuthoritativeSettings() throws {
        let suite = "utter.credentials.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let credentials = SettingsCredentialsService(settings: settings)
        let original = credentials.snapshot.developerHTTPToken
        var observed: [CredentialsSnapshot] = []
        let token = credentials.observe { observed.append($0) }
        credentials.resetDeveloperHTTPToken()
        XCTAssertNotEqual(credentials.snapshot.developerHTTPToken, original)
        XCTAssertEqual(credentials.snapshot.developerHTTPToken, settings.values.developerHTTPToken)
        XCTAssertEqual(observed.last, credentials.snapshot)
        credentials.removeObserver(token)
        let count = observed.count
        credentials.update { $0.remoteAPIKey = "fixture" }
        XCTAssertEqual(observed.count, count)
    }
}
