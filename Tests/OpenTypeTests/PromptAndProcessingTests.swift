import XCTest
@testable import OpenType

@MainActor
final class PromptAndProcessingTests: XCTestCase {
    private func withCleanSettings(_ body: () throws -> Void) rethrows {
        let settings = AppSettings.shared
        let savedUseCustomSystemPrompt = settings.useCustomSystemPrompt
        let savedCustomSystemPrompt = settings.customSystemPrompt
        let savedInputLanguage = settings.inputLanguage
        let savedLanguageStyle = settings.languageStyle
        let savedEnableMemory = settings.enableMemory
        let savedMemoryWindow = settings.memoryWindowMinutes
        let savedEnableInstantInsert = settings.enableInstantInsert
        let savedEntries = PersonalDictionary.shared.entries
        let savedRules = PersonalDictionary.shared.editRules
        settings.useCustomSystemPrompt = false
        settings.customSystemPrompt = ""
        settings.inputLanguage = .chinese
        settings.languageStyle = .professional
        settings.enableMemory = true
        settings.memoryWindowMinutes = 30
        settings.enableInstantInsert = false
        PersonalDictionary.shared.entries = []
        PersonalDictionary.shared.editRules = []
        defer {
            settings.useCustomSystemPrompt = savedUseCustomSystemPrompt
            settings.customSystemPrompt = savedCustomSystemPrompt
            settings.inputLanguage = savedInputLanguage
            settings.languageStyle = savedLanguageStyle
            settings.enableMemory = savedEnableMemory
            settings.memoryWindowMinutes = savedMemoryWindow
            settings.enableInstantInsert = savedEnableInstantInsert
            PersonalDictionary.shared.entries = savedEntries
            PersonalDictionary.shared.editRules = savedRules
        }
        try body()
    }

    func testPersonalDictionaryReplacementsAndRules() {
        withCleanSettings {
            let dictionary = PersonalDictionary.shared
            dictionary.entries = [
                DictionaryEntry(original: "open type", replacement: "OpenType", enabled: true),
                DictionaryEntry(original: "blank replacement", replacement: "", enabled: true),
                DictionaryEntry(original: "skip me", replacement: "wrong", enabled: false),
            ]
            dictionary.editRules = [
                EditRule(description: " Keep product names exact. ", enabled: true),
                EditRule(description: "   ", enabled: true),
                EditRule(description: "Disabled rule.", enabled: false),
            ]

            XCTAssertEqual(dictionary.applyReplacements(to: "open type should not skip me"), "OpenType should not skip me")
            XCTAssertEqual(dictionary.activeEntriesDescription(), "open type -> OpenType")
            XCTAssertEqual(dictionary.activeRulesDescription(), "Keep product names exact.")
        }
    }

    func testBasicCleanAppliesDictionaryAndNormalizesWhitespace() {
        withCleanSettings {
            PersonalDictionary.shared.entries = [
                DictionaryEntry(original: "open type", replacement: "OpenType", enabled: true)
            ]

            let processor = TextProcessor()
            XCTAssertEqual(processor.basicClean(text: "  open type\n\n  is\tfast  "), "OpenType\n\nis fast")
        }
    }

    func testBasicCleanDoesNotInterpretSpokenFormattingIntent() {
        let processor = TextProcessor()

        XCTAssertEqual(
            processor.basicClean(
                text: "open type no space cli comma all caps api key",
                inputLanguage: .english
            ),
            "open type no space cli comma all caps api key"
        )
    }

    func testGeneratedOutputFallsBackWhenLLMReturnsOnlyThinking() {
        let processor = TextProcessor()

        XCTAssertEqual(
            processor.cleanGeneratedOutput(
                "<think>working through the rewrite</think>",
                inputLanguage: .english,
                fallback: "raw transcript"
            ),
            "raw transcript"
        )
    }

    func testGeneratedOutputCanRejectEmptyLLMResultWithoutFallback() {
        let processor = TextProcessor()

        XCTAssertEqual(
            processor.cleanGeneratedOutput(
                "<think>working through the rewrite</think>",
                inputLanguage: .english
            ),
            ""
        )
    }

    func testCommandGeneratedOutputDoesNotFallBackToRawVoiceCommand() {
        let processor = TextProcessor()

        XCTAssertEqual(
            processor.cleanCommandGeneratedOutput(
                "<think>deciding what to do</think>",
                inputLanguage: .english
            ),
            ""
        )
    }

    func testCommandGeneratedOutputPreservesReplacementPunctuation() {
        let processor = TextProcessor()

        XCTAssertEqual(
            processor.cleanCommandGeneratedOutput("  OK!  ", inputLanguage: .english),
            "OK!"
        )
        XCTAssertEqual(
            processor.cleanCommandGeneratedOutput("真的吗？", inputLanguage: .chinese),
            "真的吗？"
        )
    }

    func testSystemPromptWithPersonalContextUsesDictionaryAndRulesForLLM() {
        withCleanSettings {
            PersonalDictionary.shared.entries = [
                DictionaryEntry(original: "open type", replacement: "OpenType", enabled: true),
                DictionaryEntry(original: "disabled", replacement: "Disabled", enabled: false),
            ]
            PersonalDictionary.shared.editRules = [
                EditRule(description: "Always keep OpenType capitalized.", enabled: true),
                EditRule(description: "Ignore disabled rules.", enabled: false),
            ]

            let processor = TextProcessor()
            let chinese = processor.systemPromptWithPersonalContext(
                "基础提示",
                inputLanguage: .chinese
            )
            let english = processor.systemPromptWithPersonalContext(
                "Base prompt",
                inputLanguage: .english
            )

            XCTAssertTrue(chinese.contains("个人词库："))
            XCTAssertTrue(chinese.contains("open type -> OpenType"))
            XCTAssertTrue(chinese.contains("额外编辑规则："))
            XCTAssertTrue(chinese.contains("Always keep OpenType capitalized."))
            XCTAssertFalse(chinese.contains("Disabled"))
            XCTAssertFalse(chinese.contains("Ignore disabled rules."))
            XCTAssertTrue(english.contains("Personal dictionary:"))
            XCTAssertTrue(english.contains("open type -> OpenType"))
            XCTAssertTrue(english.contains("Extra edit rules:"))
            XCTAssertTrue(english.contains("Always keep OpenType capitalized."))
        }
    }

    func testPrepareForFormattingKeepsSemanticCleanupForLLM() {
        withCleanSettings {
            let processor = TextProcessor()
            let cleaned = processor.prepareForFormatting(
                text: "嗯 那个 今天下午开会",
                inputLanguage: .chinese
            )

            XCTAssertEqual(cleaned, "嗯 那个 今天下午开会")
        }
    }

    func testPrepareForFormattingLeavesListIntentForLLM() {
        withCleanSettings {
            let processor = TextProcessor()
            let cleaned = processor.prepareForFormatting(
                text: "第一先把需求过一下 第二确认时间 第三把预算拉出来",
                inputLanguage: .chinese
            )

            XCTAssertEqual(cleaned, "第一先把需求过一下 第二确认时间 第三把预算拉出来")
        }
    }

    func testPrepareForFormattingLeavesStandaloneDeleteCommandForLLMOrCommandPath() {
        withCleanSettings {
            let processor = TextProcessor()
            let cleaned = processor.prepareForFormatting(
                text: "delete that",
                inputLanguage: .english
            )

            XCTAssertEqual(cleaned, "delete that")
        }
    }

    func testFormattingOptionsUseStyleSpecificBudgets() {
        withCleanSettings {
            let processor = TextProcessor()

            XCTAssertEqual(processor.formattingOptions(for: "短句", style: .professional).maxTokens, 224)
            XCTAssertEqual(processor.formattingOptions(for: String(repeating: "中", count: 120), style: .professional).maxTokens, 384)
            XCTAssertEqual(processor.formattingOptions(for: String(repeating: "长", count: 260), style: .professional).maxTokens, 640)
            XCTAssertEqual(processor.formattingOptions(for: "short", style: .casual).maxTokens, 160)
            XCTAssertEqual(processor.formattingOptions(for: String(repeating: "c", count: 120), style: .casual).maxTokens, 256)
            XCTAssertEqual(processor.formattingOptions(for: String(repeating: "c", count: 260), style: .casual).maxTokens, 384)
            XCTAssertEqual(processor.formattingOptions(for: "短句", style: .casual).temperature, 0.08)
            XCTAssertEqual(processor.formattingOptions(for: "短句", style: .professional).temperature, 0.10)
        }
    }

}
