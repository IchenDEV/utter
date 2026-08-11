import Foundation
import XCTest
@testable import OpenType

final class PersonalDictionaryLearningTests: XCTestCase {
    func testLegacyEntryDecodesAsActiveManualTerm() throws {
        let data = Data(#"{"original":"open type","replacement":"OpenType","enabled":true}"#.utf8)
        let entry = try JSONDecoder().decode(DictionaryEntry.self, from: data)

        XCTAssertEqual(entry.origin, .manual)
        XCTAssertEqual(entry.status, .active)
        XCTAssertTrue(entry.isEffective)
    }

    func testManualTermWorksImmediately() throws {
        let store = makeStore()
        XCTAssertNotNil(store.addEntry(original: "open type", replacement: "OpenType"))

        XCTAssertEqual(store.applyReplacements(to: "Use open type."), "Use OpenType.")
        XCTAssertEqual(SpeechRecognitionContext(dictionaryEntries: store.entries).phrases, ["OpenType"])
    }

    func testAmbiguousLearnedTermRequiresTwoIndependentRecords() throws {
        let store = makeStore()
        let first = learnedCandidate(recordID: UUID(), confidence: 0.82)
        let second = learnedCandidate(recordID: UUID(), confidence: 0.82)

        let entryID = try XCTUnwrap(store.recordLearnedCandidate(first))
        XCTAssertEqual(store.entries.first(where: { $0.id == entryID })?.status, .pending)
        XCTAssertEqual(store.applyReplacements(to: "菜单蓝"), "菜单蓝")
        XCTAssertTrue(SpeechRecognitionContext(dictionaryEntries: store.entries).phrases.isEmpty)

        store.recordLearnedCandidate(second)
        XCTAssertEqual(store.entries.first(where: { $0.id == entryID })?.status, .active)
        XCTAssertEqual(store.applyReplacements(to: "菜单蓝"), "菜单栏")
    }

    func testHighConfidenceLearnedTermActivatesOnceAndManualEntryWins() throws {
        let store = makeStore()
        store.recordLearnedCandidate(LearnedCorrectionCandidate(
            original: "open type",
            replacement: "OpenType",
            confidence: 0.98,
            sourceRecordID: UUID(),
            languageCode: "en",
            bundleIdentifier: "com.apple.Notes"
        ))
        XCTAssertEqual(store.entries.first?.status, .active)

        store.addEntry(original: "open type", replacement: "OpenType Pro")
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.origin, .manual)
        XCTAssertEqual(store.applyReplacements(to: "open type"), "OpenType Pro")
    }

    func testConflictingLearnedMappingsRemainPendingUntilOneIsApproved() throws {
        let store = makeStore()
        store.recordLearnedCandidate(LearnedCorrectionCandidate(
            original: "open tape",
            replacement: "OpenType",
            confidence: 0.98,
            sourceRecordID: UUID(),
            languageCode: "en",
            bundleIdentifier: nil
        ))
        let competingID = try XCTUnwrap(store.recordLearnedCandidate(LearnedCorrectionCandidate(
            original: "open tape",
            replacement: "Open Tape",
            confidence: 0.98,
            sourceRecordID: UUID(),
            languageCode: "en",
            bundleIdentifier: nil
        )))

        XCTAssertEqual(store.entries.map(\.status), [.pending, .pending])
        XCTAssertEqual(store.applyReplacements(to: "open tape"), "open tape")

        store.approveEntry(id: competingID)
        XCTAssertEqual(store.applyReplacements(to: "open tape"), "Open Tape")
        XCTAssertEqual(store.entries.filter(\.isEffective).count, 1)
    }

    private func learnedCandidate(recordID: UUID, confidence: Double) -> LearnedCorrectionCandidate {
        LearnedCorrectionCandidate(
            original: "蓝",
            replacement: "栏",
            confidence: confidence,
            sourceRecordID: recordID,
            languageCode: "zh",
            bundleIdentifier: "com.apple.Notes"
        )
    }

    private func makeStore() -> PersonalDictionary {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeDictionaryTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return PersonalDictionary(directoryURL: url)
    }
}
