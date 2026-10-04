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

final class SettingsProjectionTests: XCTestCase {
    func testProjectionWritesThroughToTheInjectedAuthority() {
        let name = "SettingsProjection-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let service = SettingsStore(defaults: defaults)
        let settings = AppSettings(service: service)
        var observed: [Bool] = []
        let observation = settings.publisher(for: \.remoteMicEnabled).sink { observed.append($0) }
        settings.remoteMicEnabled = true
        service.update { $0.remoteMicEnabled = false }
        XCTAssertEqual(observed, [false, true, false])
        XCTAssertFalse(settings.remoteMicEnabled)
        XCTAssertFalse(defaults.bool(forKey: "remoteMicEnabled"))
        withExtendedLifetime(observation) {}
    }

    func testReadOnlyComputedValuesAndWritableBindingsUseTheSameSnapshot() {
        let name = "SettingsProjection-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let service = SettingsStore(defaults: defaults)
        let settings = AppSettings(service: service)
        let key: ReferenceWritableKeyPath<AppSettings, UILanguage> = \.uiLanguage
        settings[keyPath: key] = .english
        XCTAssertFalse(settings.zh)
        XCTAssertEqual(settings.snapshot.uiLanguage, .english)
        XCTAssertEqual(service.values.uiLanguage, .english)
    }
}
