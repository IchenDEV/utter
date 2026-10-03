import UtterRemoteMic
import Foundation
import XCTest
import UtterPresentationContracts
@testable import OpenType

final class RemoteMicGainSettingsTests: XCTestCase {
    func testRemoteMicGainAllowsPersistedZeroDB() {
        let suite = "RemoteMicProtocolTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(0.0, forKey: "remoteMicGainDB")
        XCTAssertEqual(AppSettings(defaults: defaults).remoteMicGainDB, 0)
    }

    func testRemoteMicGainDefaultsOnlyWhenTheKeyIsAbsent() {
        let suite = "RemoteMicProtocolTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(
            AppSettings(defaults: defaults).remoteMicGainDB,
            RemoteMicProtocol.defaultGainDB
        )
    }
}
