import XCTest
@testable import OpenType

final class FormattedOutputCleanerTests: XCTestCase {
    func testKeepsOnlyMarkedFinalText() {
        let llmOutput = """
        ---

        **整理后文本：**

        接下来，将整个系统的十八 n 语言 Flow 全部重新做了。
        所有十八 n 文案维护在一个单独的 package 里头，叫 ec at ec 杠 i 幺八 n。

        ---

        **说明：**
        1. **纠错与同音词修正**：
        * 原文“十八 n”在上下文中多次出现。
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            """
            接下来，将整个系统的十八 n 语言 Flow 全部重新做了。
            所有十八 n 文案维护在一个单独的 package 里头，叫 ec at ec 杠 i 幺八 n。
            """
        )
    }

    func testKeepsUnmarkedExplanationLookingSection() {
        // Dictated content legitimately contains "说明：" lines. Without a
        // final-text label there is no safe way to tell model scaffolding from
        // user content, so nothing is dropped.
        let llmOutput = """
        接下来，将 i18n 文案迁移到 @ec/i18n。

        说明：
        新增了两个字段，注意向后兼容。
        """

        XCTAssertEqual(FormattedOutputCleaner.clean(llmOutput), llmOutput)
    }

    func testKeepsContentStartingWithExplanationHeading() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("Explanation:\nThis label is part of the requested text."),
            "Explanation:\nThis label is part of the requested text."
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("说明：\n这是用户要求保留的正文标签。"),
            "说明：\n这是用户要求保留的正文标签。"
        )
    }

    func testKeepsSingleLineContentStartingWithFinalTextLabel() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("Final text: this label is part of the requested text."),
            "Final text: this label is part of the requested text."
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("最终文本：这是用户要求保留的正文标签。"),
            "最终文本：这是用户要求保留的正文标签。"
        )
    }

    func testRemovesInlineFinalTextWrapperWhenExplanationFollows() {
        let llmOutput = """
        Final text: Ship the release notes today.

        Explanation:
        Removed filler words.
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testDoesNotInventListBreaks() {
        let llmOutput = "首先确认需求 其次同步时间 最后发出纪要"

        XCTAssertEqual(FormattedOutputCleaner.clean(llmOutput), llmOutput)
    }

    func testRemovesWrappingCodeFence() {
        let llmOutput = """
        Final text:
        ```text
        Ship the release notes today.
        ```

        Explanation:
        Removed filler words.
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(llmOutput),
            "Ship the release notes today."
        )
    }

    func testRemovesConversationalLeadInLabels() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("Here is the final text:\nShip the release notes today."),
            "Ship the release notes today."
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("以下是整理后的文本：\n今天下午同步发布计划。"),
            "今天下午同步发布计划。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("こちらが最終テキスト：\n金曜の午後に会議します。"),
            "金曜の午後に会議します。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("다음은 최종 텍스트입니다:\n금요일 오후에 회의합니다."),
            "금요일 오후에 회의합니다."
        )
    }

    func testRemovesJapaneseAndKoreanMarkedFinalText() {
        let japanese = """
        出力：金曜の午後に会議します。

        説明：
        言い直しを整理しました。
        """
        let korean = """
        최종 텍스트:
        금요일 오후에 회의합니다.

        설명:
        말 바꿈을 정리했습니다.
        """

        XCTAssertEqual(
            FormattedOutputCleaner.clean(japanese),
            "金曜の午後に会議します。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean(korean),
            "금요일 오후에 회의합니다."
        )
    }

    func testKeepsDictatedJSONVerbatim() {
        // The cleaner never mines JSON out of the text: dictated JSON examples
        // must survive untouched. Structured API payloads are unwrapped at the
        // RemoteLLMResponseText boundary instead.
        let dictatedObjects = [
            #"{"final_text":"Ship the release notes today.","explanation":"Removed filler words."}"#,
            #"{"text": "hello", "confidence": 0.9}"#,
            #"{"name":"OpenType","mode":"voice"}"#,
            #"{"text":"Ship the release notes today.","mode":"voice"}"#,
            #"The payload is {"text":"Ship the release notes today.","mode":"voice"}."#,
            #"请把 {"final_text": "你好"} 这个例子记录一下"#,
        ]

        for text in dictatedObjects {
            XCTAssertEqual(FormattedOutputCleaner.clean(text), text)
        }
    }

    func testStripsInlineNarrationPrefixes() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("好的，以下是整理后的文本：我们周五下午开会。"),
            "我们周五下午开会。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("整理后的文本是：我们周五下午开会。"),
            "我们周五下午开会。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("下面这段话整理后是：我们周五下午开会。"),
            "我们周五下午开会。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("Sure, here is the rewritten text: Ship the release notes."),
            "Ship the release notes."
        )
    }

    func testKeepsBareLabelsThatCouldBeDictation() {
        // "输出结果：" and similar short labels are plausible dictated openings;
        // only meta-narration about rewriting is stripped inline.
        XCTAssertEqual(
            FormattedOutputCleaner.clean("输出结果：全部测试通过。"),
            "输出结果：全部测试通过。"
        )
    }

    func testStripsEchoedTripleAngleWrapper() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("<<<\n我们周五下午开会。\n>>>"),
            "我们周五下午开会。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("<<<我们周五下午开会。>>>"),
            "我们周五下午开会。"
        )
    }

    func testKeepsDictatedTripleAngleMentions() {
        let text = "heredoc 的写法是 <<<EOF 然后结束"
        XCTAssertEqual(FormattedOutputCleaner.clean(text), text)
    }

    func testKeepsContentStartingWithJapaneseOrKoreanExplanationHeading() {
        XCTAssertEqual(
            FormattedOutputCleaner.clean("説明：\nこれは本文の見出しです。"),
            "説明：\nこれは本文の見出しです。"
        )
        XCTAssertEqual(
            FormattedOutputCleaner.clean("설명:\n이 라벨은 본문입니다."),
            "설명:\n이 라벨은 본문입니다."
        )
    }
}
