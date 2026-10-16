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

        let workflow = try VoiceWorkflowFixture()
        defer { workflow.remove() }
        XCTAssertEqual(workflow.directory.deletingLastPathComponent(), TestFixtureRoot.root)
        let workflowFile = try XCTUnwrap(workflow.files.url).appendingPathComponent("literal.txt")
        try literal.write(to: workflowFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: workflowFile, encoding: .utf8), literal)

        let original = "owned-dictionary-source-20261014"
        let entryID = try XCTUnwrap(PersonalDictionary.shared.addEntry(original: original, replacement: literal))
        defer { PersonalDictionary.shared.removeEntry(id: entryID) }
        let dictionaryFile = TestFixtureRoot.root.appendingPathComponent("Dictionary/dictionary.json")
        let entries = try decoder.decode([DictionaryEntry].self, from: Data(contentsOf: dictionaryFile))
        XCTAssertEqual(entries.first(where: { $0.id == entryID })?.original, original)
        XCTAssertEqual(entries.first(where: { $0.id == entryID })?.replacement, literal)
        XCTAssertEqual(PersonalDictionary.shared.applyReplacements(to: original), literal)
        XCTAssertTrue(PersonalDictionary.shared.storageAvailable)

        let evidence = try NativeE2EUI.directory(override: nil)
        XCTAssertEqual(evidence.deletingLastPathComponent(), TestFixtureRoot.root)
        let evidenceFile = evidence.appendingPathComponent("logs/literal.txt")
        try literal.write(to: evidenceFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: evidenceFile, encoding: .utf8), literal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.appendingPathComponent("screenshots").path))
        let explicitEvidence = TestFixtureRoot.root.appendingPathComponent("ExplicitNativeEvidence", isDirectory: true)
        XCTAssertEqual(try NativeE2EUI.directory(override: explicitEvidence.path), explicitEvidence)
        try NativeE2EUI.record("fixture-isolation", ["payload": literal])
        let recordFile = try NativeE2EUI.directory().appendingPathComponent("logs/fixture-isolation.json")
        let record = try JSONSerialization.jsonObject(with: Data(contentsOf: recordFile)) as? [String: String]
        XCTAssertEqual(record?["payload"], literal)
        let blockedEvidence = TestFixtureRoot.root.appendingPathComponent("evidence-is-a-file")
        try literal.write(to: blockedEvidence, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try NativeE2EUI.directory(override: blockedEvidence.path))
    }
}
