import XCTest
@testable import OpenType

@MainActor
final class MultilingualPromptTests: XCTestCase {
    private func withDefaultPromptSettings(_ body: () throws -> Void) rethrows {
        let settings = AppSettings.shared
        let savedUseCustomSystemPrompt = settings.useCustomSystemPrompt
        let savedCustomSystemPrompt = settings.customSystemPrompt
        let savedLanguageStyle = settings.languageStyle
        settings.useCustomSystemPrompt = false
        settings.customSystemPrompt = ""
        settings.languageStyle = .professional
        defer {
            settings.useCustomSystemPrompt = savedUseCustomSystemPrompt
            settings.customSystemPrompt = savedCustomSystemPrompt
            settings.languageStyle = savedLanguageStyle
        }
        try body()
    }

    func testJapaneseSmartFormatPromptUsesJapaneseInstructions() {
        withDefaultPromptSettings {
            let user = PromptBuilder.buildUserPrompt(text: "えっと金曜に会議", inputLanguage: .japanese)
            let system = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "",
                inputLanguage: .japanese
            )

            XCTAssertTrue(user.contains("日本語の音声認識原文"))
            XCTAssertTrue(system.contains("日本語の音声入力後処理"))
            XCTAssertTrue(system.contains("ASR 品質ルール"))
            XCTAssertTrue(system.contains("OpenType、hotkey、menu bar、API、JSON、i18n、URL"))
            XCTAssertTrue(system.contains("スタイル：専門的に整理"))
            XCTAssertTrue(system.contains("final_text"))
            XCTAssertTrue(system.contains("専門整理の補足例"))
            XCTAssertFalse(system.contains("Professional cleanup examples"))
        }
    }

    func testKoreanSmartFormatPromptUsesKoreanInstructions() {
        withDefaultPromptSettings {
            let user = PromptBuilder.buildUserPrompt(text: "음 금요일에 회의", inputLanguage: .korean)
            let system = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "",
                inputLanguage: .korean
            )

            XCTAssertTrue(user.contains("한국어 음성 인식 원문"))
            XCTAssertTrue(system.contains("한국어 음성 입력 후처리기"))
            XCTAssertTrue(system.contains("ASR 품질 규칙"))
            XCTAssertTrue(system.contains("OpenType, hotkey, menu bar, API, JSON, i18n, URL"))
            XCTAssertTrue(system.contains("스타일: 전문적으로 정리"))
            XCTAssertTrue(system.contains("final_text"))
            XCTAssertTrue(system.contains("전문 정리 보충 예시"))
            XCTAssertFalse(system.contains("Professional cleanup examples"))
        }
    }

    func testJapaneseAndKoreanCommandPromptsUseTargetLanguageRules() {
        let japanese = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "メール本文",
            memoryContext: "前回の入力",
            inputLanguage: .japanese
        )
        let korean = PromptBuilder.buildCommandSystemPrompt(
            screenContext: "메일 본문",
            memoryContext: "이전 입력",
            inputLanguage: .korean
        )

        XCTAssertTrue(PromptBuilder.buildCommandUserPrompt(text: "返信して", inputLanguage: .japanese).contains("日本語の音声指令"))
        XCTAssertTrue(japanese.contains("日本語の音声アシスタント"))
        XCTAssertTrue(japanese.contains("ユーザーの現在画面にある文字内容"))
        XCTAssertTrue(japanese.contains("最近の入力履歴"))

        XCTAssertTrue(PromptBuilder.buildCommandUserPrompt(text: "답장해줘", inputLanguage: .korean).contains("한국어 음성 명령"))
        XCTAssertTrue(korean.contains("한국어 음성 어시스턴트"))
        XCTAssertTrue(korean.contains("사용자의 현재 화면 텍스트"))
        XCTAssertTrue(korean.contains("최근 입력 기록"))
    }

    func testSmartFormatContextUsesTargetLanguageLabels() {
        let japaneseContext = InputContext(
            appName: "メモ",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "議事録",
            outputMode: .processed,
            inputLanguage: .japanese,
            source: .menuBar
        )
        let koreanContext = InputContext(
            appName: "메모",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "회의록",
            outputMode: .processed,
            inputLanguage: .korean,
            source: .menuBar
        )
        let japanese = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            screenContext: "OpenType 設定",
            screenImageAvailable: true,
            memoryContext: "前回 hotkey と言った",
            inputContext: japaneseContext,
            inputLanguage: .japanese
        )
        let korean = PromptBuilder.buildSystemPrompt(
            style: .professional,
            stylePrompt: "",
            screenContext: "OpenType 설정",
            screenImageAvailable: true,
            memoryContext: "이전에 hotkey를 말함",
            inputContext: koreanContext,
            inputLanguage: .korean
        )

        XCTAssertTrue(japanese.contains("画面上のテキスト"))
        XCTAssertTrue(japanese.contains("画面スクリーンショット"))
        XCTAssertTrue(japanese.contains("最近の入力"))
        XCTAssertTrue(japanese.contains("現在の入力先"))
        XCTAssertTrue(japanese.contains("- アプリ: メモ"))
        XCTAssertTrue(japanese.contains("現在時刻"))
        XCTAssertFalse(japanese.contains("On-screen text for correction"))

        XCTAssertTrue(korean.contains("화면 텍스트"))
        XCTAssertTrue(korean.contains("화면 스크린샷"))
        XCTAssertTrue(korean.contains("최근 입력"))
        XCTAssertTrue(korean.contains("현재 입력 대상"))
        XCTAssertTrue(korean.contains("- 앱: 메모"))
        XCTAssertTrue(korean.contains("현재 시간"))
        XCTAssertFalse(korean.contains("On-screen text for correction"))
    }

    func testJapaneseAndKoreanEditCommandResolverPromptsUseTargetLanguageRules() {
        let japaneseSystem = PromptBuilder.buildEditCommandResolverSystemPrompt(inputLanguage: .japanese)
        let koreanSystem = PromptBuilder.buildEditCommandResolverSystemPrompt(inputLanguage: .korean)
        let japaneseUser = PromptBuilder.buildEditCommandResolverUserPrompt(
            text: "この部分を短くして",
            inputLanguage: .japanese,
            context: SpokenEditCommandResolutionContext(lastInsertion: .unavailable, selectedText: .unknown)
        )
        let koreanUser = PromptBuilder.buildEditCommandResolverUserPrompt(
            text: "이 부분을 짧게 줄여줘",
            inputLanguage: .korean,
            context: SpokenEditCommandResolutionContext(lastInsertion: .available, selectedText: .unavailable)
        )

        XCTAssertTrue(japaneseSystem.contains("音声入力メソッド"))
        XCTAssertTrue(japaneseSystem.contains("通常の聞き取り"))
        XCTAssertTrue(japaneseSystem.contains(#""action":"rewrite_selection","intent":"meeting_notes""#))
        XCTAssertTrue(japaneseUser.contains("直前の OpenType 挿入：利用不可"))
        XCTAssertTrue(japaneseUser.contains("現在の選択範囲：不明"))
        XCTAssertFalse(japaneseUser.contains("Runtime state"))

        XCTAssertTrue(koreanSystem.contains("음성 입력기"))
        XCTAssertTrue(koreanSystem.contains("일반 받아쓰기"))
        XCTAssertTrue(koreanSystem.contains(#""action":"rewrite_selection","intent":"meeting_notes""#))
        XCTAssertTrue(koreanUser.contains("직전 OpenType 삽입: 사용 가능"))
        XCTAssertTrue(koreanUser.contains("현재 선택 영역: 사용 불가"))
        XCTAssertFalse(koreanUser.contains("Runtime state"))
    }

    func testSelectionEditPromptsUseTargetLanguageLabelsAndInstructions() {
        let processor = TextProcessor()
        let japanese = processor.selectionEditPrompt(
            selectedText: "金曜までにリリースノートを整える",
            intent: .casual,
            inputLanguage: .japanese,
            memoryContext: "前回 OpenType と言った"
        )
        let korean = processor.selectionEditPrompt(
            selectedText: "금요일까지 릴리스 노트를 정리한다",
            intent: .meetingNotes,
            inputLanguage: .korean,
            memoryContext: "이전에 OpenType를 말함"
        )
        let cantonese = processor.selectionEditPrompt(
            selectedText: "今日發版",
            intent: .casual,
            inputLanguage: .cantonese
        )
        let automatic = processor.selectionEditPrompt(
            selectedText: "今天发版",
            intent: .concise,
            inputLanguage: .auto
        )

        XCTAssertTrue(japanese.contains("指示："))
        XCTAssertTrue(japanese.contains("選択テキスト："))
        XCTAssertTrue(japanese.contains("自然で親しみやすい"))
        XCTAssertTrue(japanese.contains("最近の入力"))
        XCTAssertFalse(japanese.contains("Selected text:"))

        XCTAssertTrue(korean.contains("지시:"))
        XCTAssertTrue(korean.contains("선택 텍스트:"))
        XCTAssertTrue(korean.contains("회의록"))
        XCTAssertTrue(korean.contains("최근 입력"))
        XCTAssertFalse(korean.contains("Selected text:"))

        XCTAssertTrue(cantonese.contains("指令："))
        XCTAssertTrue(cantonese.contains("选中文本："))
        XCTAssertTrue(cantonese.contains("口语"))
        XCTAssertFalse(cantonese.contains("Selected text:"))

        XCTAssertTrue(automatic.contains("指令："))
        XCTAssertTrue(automatic.contains("选中文本："))
        XCTAssertTrue(automatic.contains("压缩"))
        XCTAssertFalse(automatic.contains("Selected text:"))
    }

    func testSelectionEditSystemPromptsUseTargetLanguageRules() {
        let processor = TextProcessor()

        XCTAssertTrue(processor.selectionEditSystemPrompt(inputLanguage: .japanese).contains("選択テキスト処理エンジン"))
        XCTAssertTrue(processor.selectionEditSystemPrompt(inputLanguage: .korean).contains("선택 텍스트 처리기"))
        XCTAssertTrue(processor.selectionEditSystemPrompt(inputLanguage: .cantonese).contains("选中文本处理器"))
        XCTAssertTrue(processor.selectionEditSystemPrompt(inputLanguage: .auto).contains("选中文本处理器"))
    }

    func testCustomSystemPromptOutputContractUsesTargetLanguage() {
        withDefaultPromptSettings {
            AppSettings.shared.useCustomSystemPrompt = true
            AppSettings.shared.customSystemPrompt = "Keep product names exact."

            let japanese = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "",
                inputLanguage: .japanese
            )
            let korean = PromptBuilder.buildSystemPrompt(
                style: .professional,
                stylePrompt: "",
                inputLanguage: .korean
            )
            XCTAssertTrue(japanese.contains("入力メソッド出力契約"))
            XCTAssertTrue(japanese.contains("挿入可能な最終テキストだけ"))
            XCTAssertTrue(japanese.contains("final_text"))
            XCTAssertFalse(japanese.contains("Input method output contract"))

            XCTAssertTrue(korean.contains("입력기 출력 계약"))
            XCTAssertTrue(korean.contains("삽입 가능한 최종 텍스트만"))
            XCTAssertTrue(korean.contains("final_text"))
            XCTAssertFalse(korean.contains("Input method output contract"))
        }
    }
}
