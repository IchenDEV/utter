import Foundation
import XCTest
import UtterContracts
@testable import UtterData

final class SettingsStoreTests: XCTestCase {
    func testSessionSnapshotStaysFrozenAndReopeningPreservesChanges() {
        let fixture = defaultsFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let store = SettingsStore(defaults: fixture.defaults)
        let frozen = store.values
        store.update { values in
            values.speechEngine = .whisper
            values.remoteProvider = .claude
            values.remoteAPIKey = "synthetic-secret"
            values.modelStoragePath = "/tmp/synthetic-models"
            values.localWhisperModelPaths = ["local/test": "/tmp/whisper"]
            values.allowClipboardPaste = false
        }
        XCTAssertEqual(frozen.speechEngine, .apple)
        XCTAssertEqual(frozen.remoteAPIKey, "")
        XCTAssertTrue(frozen.allowClipboardPaste)
        let reopened = SettingsStore(defaults: fixture.defaults)
        XCTAssertEqual(reopened.values, store.values)
        XCTAssertEqual(fixture.defaults.string(forKey: "speechEngine"), "whisper")
        XCTAssertEqual(fixture.defaults.string(forKey: "remoteAPIKey"), "synthetic-secret")
        XCTAssertFalse(reopened.values.allowClipboardPaste)
    }

    func testCompoundUpdateNotifiesOnceAfterPersistenceAndHotkeyNormalization() {
        let fixture = defaultsFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let store = SettingsStore(defaults: fixture.defaults)
        var notifications: [SettingsValues] = []
        let token = store.observe { values in
            notifications.append(values)
            XCTAssertEqual(values, store.values)
            XCTAssertEqual(fixture.defaults.string(forKey: "hotkeyType"), values.hotkeyType.rawValue)
        }
        store.update { values in
            values.hotkeyType = .shift
            values.translationHotkeyModifier = .shift
            values.enableMemory = false
        }
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(store.values.translationHotkeyModifier, .option)
        store.removeObserver(token)
        store.update { $0.enableMemory = true }
        XCTAssertEqual(notifications.count, 1)
    }

    func testLegacyMigrationAndExplicitZeroGainRemainCompatible() {
        let fixture = defaultsFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        fixture.defaults.set("mimo", forKey: "speechEngine")
        fixture.defaults.set("/tmp/old-runtime", forKey: "mimoASRRepoPath")
        fixture.defaults.set(0, forKey: "remoteMicGainDB")
        fixture.defaults.set(99_999, forKey: "developerHTTPPort")
        fixture.defaults.set("zh", forKey: "uiLanguage")
        let store = SettingsStore(defaults: fixture.defaults)
        XCTAssertEqual(store.values.speechEngine, .apple)
        XCTAssertNil(fixture.defaults.object(forKey: "mimoASRRepoPath"))
        XCTAssertEqual(store.values.remoteMicGainDB, 0)
        XCTAssertEqual(store.values.developerHTTPPort, 38_765)
        XCTAssertEqual(store.values.uiLanguage, .chinese)
        XCTAssertEqual(fixture.defaults.string(forKey: "speechEngine"), "apple")
    }

    func testTokenRotationKeepsOriginalKeyAndDoesNotChangeComposition() throws {
        let fixture = defaultsFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let store = SettingsStore(defaults: fixture.defaults)
        let token = store.values.developerHTTPToken
        XCTAssertEqual(Data(base64Encoded: token)?.count, 32)
        store.resetDeveloperHTTPToken()
        XCTAssertNotEqual(store.values.developerHTTPToken, token)
        XCTAssertEqual(fixture.defaults.string(forKey: "developerHTTPToken"), store.values.developerHTTPToken)
        let data = try JSONEncoder().encode(CompositionDocument(bundles: [], plugins: [], bindings: [:]))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(store.values.developerHTTPToken))
    }

    func testReentrantMutationKeepsNotificationSnapshotsInOrder() {
        let fixture = defaultsFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let store = SettingsStore(defaults: fixture.defaults)
        var observed: [Int] = []
        let token = store.observe { values in
            observed.append(values.memoryWindowMinutes)
            if values.memoryWindowMinutes == 10 {
                store.update { $0.memoryWindowMinutes = 20 }
            }
        }
        store.update { $0.memoryWindowMinutes = 10 }
        store.removeObserver(token)
        XCTAssertEqual(observed, [10, 20])
        XCTAssertEqual(store.values.memoryWindowMinutes, 20)
    }

    private func defaultsFixture() -> (defaults: UserDefaults, name: String) {
        let name = "UtterSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }
}
