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
import Combine
import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterPresentationContracts

final class CredentialsProjectionTests: XCTestCase {
    func testSelectedCredentialsOwnReadsWritesAndReset() {
        withSettings { service in
            service.update { $0.remoteAPIKey = "inactive"; $0.developerHTTPToken = "inactive-token" }
            let credentials = FixtureCredentials()
            let settings = AppSettings(service: service, credentials: credentials)
            XCTAssertEqual(settings.remoteAPIKey, "selected")
            let frozen = settings.snapshot
            settings.remoteAPIKey = "updated"
            XCTAssertEqual(credentials.snapshot.remoteAPIKey, "updated")
            XCTAssertEqual(service.values.remoteAPIKey, "inactive")
            XCTAssertEqual(frozen.remoteAPIKey, "selected")
            settings.resetDeveloperHTTPToken()
            XCTAssertEqual(settings.developerHTTPToken, "reset-selected")
            XCTAssertEqual(service.values.developerHTTPToken, "inactive-token")
            settings.remoteMicEnabled = true
            XCTAssertTrue(service.values.remoteMicEnabled)
            XCTAssertEqual(credentials.snapshot.remoteAPIKey, "updated")
        }
    }

    func testCredentialChangesPublishEffectiveValuesAndDetachObservers() {
        withSettings { service in
            let credentials = FixtureCredentials()
            var settings: AppSettings? = AppSettings(service: service, credentials: credentials)
            var keys: [String] = []
            let subscription = settings!.publisher(for: \.remoteAPIKey).sink { keys.append($0) }
            credentials.update { $0.remoteAPIKey = "replacement" }
            service.update { $0.remoteAPIKey = "inactive-changed" }
            XCTAssertEqual(keys, ["selected", "replacement"])
            settings = nil
            XCTAssertTrue(credentials.observers.isEmpty)
            withExtendedLifetime(subscription) {}
        }
    }

    private func withSettings(_ operation: (SettingsStore) -> Void) {
        let name = "CredentialsProjection-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        operation(SettingsStore(defaults: defaults))
    }
}

private final class FixtureCredentials: CredentialsService {
    private(set) var snapshot = CredentialsSnapshot(remoteAPIKey: "selected", developerHTTPToken: "selected-token")
    private(set) var observers: [UUID: (CredentialsSnapshot) -> Void] = [:]
    func update(_ mutation: (inout CredentialsSnapshot) -> Void) {
        mutation(&snapshot)
        for observer in observers.values { observer(snapshot) }
    }
    func resetDeveloperHTTPToken() { update { $0.developerHTTPToken = "reset-selected" } }
    func observe(_ callback: @escaping (CredentialsSnapshot) -> Void) -> UUID {
        let id = UUID(); observers[id] = callback; return id
    }
    func removeObserver(_ id: UUID) { observers[id] = nil }
}
