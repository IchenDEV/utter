import Foundation
import XCTest
@testable import OpenType

final class PersonalDictionaryLearningTests: XCTestCase {
    func testExistingLearnedFillerIsInertButManualRuleStillWorks() {
        let bad = DictionaryEntry(
            original: "嗯。", replacement: "Do anything", origin: .learned,
            languageCode: "zh", appScopes: ["com.apple.Notes"]
        )
        let snapshot = PersonalDictionarySnapshot(entries: [bad], editRules: [])
        XCTAssertEqual(snapshot.applyReplacements(to: "嗯。"), "嗯。")
        XCTAssertFalse(snapshot.recognitionPhrases.contains("Do anything"))

        let manual = PersonalDictionarySnapshot(entries: [
            DictionaryEntry(original: "嗯。", replacement: "Do anything")
        ], editRules: [])
        XCTAssertEqual(manual.applyReplacements(to: "嗯。"), "Do anything")
    }

    func testUnsafePersistedRuleAppearsPendingWithoutRewritingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeDictionaryReload-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalDictionary(directoryURL: directory)
        let entry = DictionaryEntry(
            original: "嗯。", replacement: "Do anything", origin: .learned,
            languageCode: "zh", appScopes: ["com.apple.Notes"]
        )
        store.entries = [entry]
        store.save()
        let file = directory.appendingPathComponent("dictionary.json")
        let originalData = try Data(contentsOf: file)

        let reloaded = PersonalDictionary(directoryURL: directory)
        XCTAssertEqual(reloaded.entries.first?.status, .pending)
        XCTAssertEqual(try Data(contentsOf: file), originalData)
        reloaded.approveEntry(id: entry.id)
        XCTAssertEqual(reloaded.entries.first?.origin, .manual)
        XCTAssertEqual(reloaded.applyReplacements(to: "嗯。"), "Do anything")
    }

    func testLearnedScopeDoesNotLeakAcrossAppsOrLanguages() {
        let entry = DictionaryEntry(
            original: "open type", replacement: "OpenType", origin: .learned,
            languageCode: "en", appScopes: ["com.apple.Notes"]
        )
        let store = makeStore()
        store.entries = [entry]
        XCTAssertEqual(store.snapshot(bundleIdentifier: "com.apple.Notes", languageCode: "en")
            .applyReplacements(to: "open type"), "OpenType")
        XCTAssertEqual(store.snapshot(bundleIdentifier: "com.apple.TextEdit", languageCode: "en")
            .applyReplacements(to: "open type"), "open type")
        XCTAssertEqual(store.snapshot(bundleIdentifier: "com.apple.Notes", languageCode: "zh")
            .applyReplacements(to: "open type"), "open type")
        XCTAssertEqual(store.snapshot().applyReplacements(to: "open type"), "open type")
    }

    func testIndependentAppsDoNotMergeLearnedEvidence() throws {
        let store = makeStore()
        let first = LearnedCorrectionCandidate(
            original: "open tape", replacement: "OpenType", confidence: 0.82,
            sourceRecordID: UUID(), languageCode: "en", bundleIdentifier: "com.apple.Notes"
        )
        let second = LearnedCorrectionCandidate(
            original: "open tape", replacement: "OpenType", confidence: 0.82,
            sourceRecordID: UUID(), languageCode: "en", bundleIdentifier: "com.apple.TextEdit"
        )
        store.recordLearnedCandidate(first)
        store.recordLearnedCandidate(second)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.map(\.status), [.pending, .pending])
        XCTAssertEqual(store.snapshot(bundleIdentifier: "com.apple.Notes", languageCode: "en")
            .applyReplacements(to: "open tape"), "open tape")
    }

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
        XCTAssertEqual(store.snapshot(bundleIdentifier: "com.apple.Notes", languageCode: "zh")
            .applyReplacements(to: "菜单蓝"), "菜单蓝")
        XCTAssertTrue(SpeechRecognitionContext(dictionaryEntries: store.entries).phrases.isEmpty)

        store.recordLearnedCandidate(second)
        XCTAssertEqual(store.entries.first(where: { $0.id == entryID })?.status, .active)
        XCTAssertEqual(store.snapshot(bundleIdentifier: "com.apple.Notes", languageCode: "zh")
            .applyReplacements(to: "菜单蓝"), "菜单栏")
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
        XCTAssertEqual(store.snapshot(languageCode: "en").applyReplacements(to: "open tape"), "Open Tape")
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
