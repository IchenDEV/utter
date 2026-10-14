import Foundation
import XCTest
import UtterContracts
import UtterModels
import UtterPresentationContracts

final class TestFixtureIsolationTests: XCTestCase {
    @MainActor
    func testSharedFixturesPersistOnlyOwnedLiteralData() throws {
        let temporary = try XCTUnwrap(ProcessInfo.processInfo.environment["TMPDIR"])
        XCTAssertEqual(
            TestFixtureRoot.root.deletingLastPathComponent().resolvingSymlinksInPath(),
            URL(fileURLWithPath: temporary, isDirectory: true).resolvingSymlinksInPath()
        )
        XCTAssertNotNil(UUID(uuidString: String(TestFixtureRoot.root.lastPathComponent.dropFirst(14))))
        XCTAssertEqual(AppSettings.shared.modelStoragePath, TestFixtureRoot.models.path)
        XCTAssertEqual(ModelStorage.root, TestFixtureRoot.models)

        let literal = "owned-fixture-isolation-payload-20261014"
        TestFixtureRoot.defaults.set(literal, forKey: "fixtureIsolationPayload")
        defer { TestFixtureRoot.defaults.removeObject(forKey: "fixtureIsolationPayload") }
        let reloaded = try XCTUnwrap(UserDefaults(suiteName: TestFixtureRoot.defaultsDomain))
        XCTAssertEqual(reloaded.string(forKey: "fixtureIsolationPayload"), literal)
        let otherDomain = TestFixtureRoot.root.appendingPathComponent(UUID().uuidString).path
        let other = try XCTUnwrap(UserDefaults(suiteName: otherDomain))
        XCTAssertNil(other.string(forKey: "fixtureIsolationPayload"))

        let id = InputHistory.shared.addRecord(rawText: literal, processedText: literal, wasProcessed: false)
        defer { InputHistory.shared.deleteRecord(id) }
        let data = try Data(contentsOf: TestFixtureRoot.history.appendingPathComponent("input_history.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([InputRecord].self, from: data)
        XCTAssertEqual(records.first(where: { $0.id == id })?.rawText, literal)
        XCTAssertEqual(records.first(where: { $0.id == id })?.processedText, literal)
        XCTAssertTrue(InputHistory.shared.storageAvailable)
    }
}
