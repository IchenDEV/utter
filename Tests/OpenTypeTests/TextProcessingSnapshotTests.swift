import XCTest
@testable import OpenType

@MainActor
final class TextProcessingSnapshotTests: XCTestCase {
    func testDictionarySnapshotKeepsAllTermsAndOriginalRules() {
        var entries = (0..<105).map {
            DictionaryEntry(original: "term \($0)", replacement: "Term\($0)")
        }
        let snapshot = PersonalDictionarySnapshot(
            entries: entries,
            editRules: [EditRule(description: "Keep product names exact.")]
        )
        entries.removeAll()

        XCTAssertEqual(snapshot.protectedTerms.count, 105)
        XCTAssertEqual(snapshot.applyReplacements(to: "term 104"), "Term104")
        XCTAssertTrue(snapshot.activeEntriesDescription.contains("term 104 -> Term104"))
        XCTAssertEqual(
            snapshot.activeRulesDescription,
            "Keep product names exact."
        )
    }

    func testFormattingPromptUsesCapturedSettingsAndDictionary() {
        let settings = AppSettings.shared
        let dictionary = PersonalDictionary.shared
        let savedUseCustom = settings.useCustomSystemPrompt
        let savedCustomPrompt = settings.customSystemPrompt
        let savedEntries = dictionary.entries
        let savedRules = dictionary.editRules
        defer {
            settings.useCustomSystemPrompt = savedUseCustom
            settings.customSystemPrompt = savedCustomPrompt
            dictionary.entries = savedEntries
            dictionary.editRules = savedRules
        }

        settings.useCustomSystemPrompt = false
        settings.customSystemPrompt = ""
        dictionary.entries = [
            DictionaryEntry(original: "open type", replacement: "OpenType")
        ]
        dictionary.editRules = [EditRule(description: "Use the captured rule.")]
        let options = TextProcessingOptions(settings: settings)
        let dictionarySnapshot = dictionary.snapshot()

        settings.useCustomSystemPrompt = true
        settings.customSystemPrompt = "Changed after capture."
        dictionary.entries = [
            DictionaryEntry(original: "new term", replacement: "NewTerm")
        ]
        dictionary.editRules = []

        let prompt = TextProcessor().formattingSystemPrompt(
            options: options,
            screenContext: "",
            screenImageAvailable: false,
            memoryContext: "",
            inputContext: nil,
            dictionarySnapshot: dictionarySnapshot
        )

        XCTAssertFalse(prompt.contains("Changed after capture."))
        XCTAssertTrue(prompt.contains("open type -> OpenType"))
        XCTAssertTrue(prompt.contains("Use the captured rule."))
        XCTAssertFalse(prompt.contains("new term -> NewTerm"))
    }
}
