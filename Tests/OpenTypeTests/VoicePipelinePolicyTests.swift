import AppKit
import XCTest
@testable import OpenType

@MainActor
final class VoicePipelinePolicyTests: XCTestCase {
    private func withCleanSettings(_ body: () throws -> Void) rethrows {
        let settings = AppSettings.shared
        let savedEnableMemory = settings.enableMemory
        let savedMemoryWindow = settings.memoryWindowMinutes
        let savedEnableInstantInsert = settings.enableInstantInsert
        settings.enableMemory = true
        settings.memoryWindowMinutes = 30
        settings.enableInstantInsert = false
        defer {
            settings.enableMemory = savedEnableMemory
            settings.memoryWindowMinutes = savedMemoryWindow
            settings.enableInstantInsert = savedEnableInstantInsert
        }
        try body()
    }

    private func audioActivity(rms: Float, frames: Int = 16_000) -> AudioCaptureActivity {
        var activity = AudioCaptureActivity()
        activity.record(rms: rms, frameCount: frames)
        return activity
    }

    func testVoicePipelinePolicyUsesMemoryForSmartFormat() {
        withCleanSettings {
            var providerCalls = 0
            let inputContext = InputContext(
                appName: "Notes",
                outputMode: .processed,
                inputLanguage: .english,
                source: .menuBar
            )
            let context = VoicePipelinePolicy.memoryContext(
                for: .processed,
                settings: AppSettings.shared,
                currentContext: inputContext
            ) { minutes, currentContext in
                providerCalls += 1
                XCTAssertEqual(minutes, 30)
                XCTAssertEqual(currentContext?.appName, "Notes")
                return "smart format memory"
            }

            XCTAssertEqual(context, "smart format memory")
            XCTAssertEqual(providerCalls, 1)
        }
    }

    func testVoicePipelinePolicyKeepsMemoryForVoiceCommand() {
        withCleanSettings {
            var providerCalls = 0
            let context = VoicePipelinePolicy.memoryContext(for: .command, settings: AppSettings.shared) { minutes, _ in
                providerCalls += 1
                return "recent \(minutes)"
            }

            XCTAssertEqual(context, "recent 30")
            XCTAssertEqual(providerCalls, 1)
        }
    }

    func testVoicePipelinePolicySkipsMemoryForDirectInput() {
        withCleanSettings {
            var providerCalls = 0
            let context = VoicePipelinePolicy.memoryContext(for: .direct, settings: AppSettings.shared) { _, _ in
                providerCalls += 1
                return "should not be used"
            }

            XCTAssertEqual(context, "")
            XCTAssertEqual(providerCalls, 0)
        }
    }

    func testVoicePipelinePolicyScreenContextGating() {
        XCTAssertFalse(VoicePipelinePolicy.shouldCaptureScreenContext(outputMode: .processed, useScreenContext: false))
        XCTAssertTrue(VoicePipelinePolicy.shouldCaptureScreenContext(outputMode: .processed, useScreenContext: true))
        XCTAssertTrue(VoicePipelinePolicy.shouldCaptureScreenContext(outputMode: .command, useScreenContext: false))
        XCTAssertFalse(VoicePipelinePolicy.shouldCaptureScreenContext(outputMode: .direct, useScreenContext: true))
    }

    func testVoiceEditCommandResolutionUsesLLMFirstOnlyForCommandMode() {
        XCTAssertFalse(VoicePipelinePolicy.shouldResolveEditCommandWithLLMFirst(outputMode: .direct))
        XCTAssertFalse(VoicePipelinePolicy.shouldResolveEditCommandWithLLMFirst(outputMode: .processed))
        XCTAssertTrue(VoicePipelinePolicy.shouldResolveEditCommandWithLLMFirst(outputMode: .command))
    }

    func testVoiceEditCommandPolicyDoesNotUseLocalParserFallback() {
        XCTAssertEqual(
            VoicePipelinePolicy.editCommand(from: .command(.deleteSelection)),
            .deleteSelection
        )
        XCTAssertEqual(
            VoicePipelinePolicy.editCommand(from: .command(.rewriteLast(.formal))),
            .rewriteLast(.formal)
        )
        XCTAssertNil(VoicePipelinePolicy.editCommand(from: SpokenEditCommandLLMResolution.none))
        XCTAssertNil(VoicePipelinePolicy.editCommand(from: nil))
    }

    func testNonCommandModesDoNotLetLocalParserStealEditPhrases() async {
        let settings = AppSettings.shared
        let savedOutputMode = settings.outputMode
        let savedInputLanguage = settings.inputLanguage
        defer {
            settings.outputMode = savedOutputMode
            settings.inputLanguage = savedInputLanguage
        }

        let pipeline = VoicePipeline(appState: AppState())
        settings.inputLanguage = .english

        settings.outputMode = .direct
        let directCommand = await pipeline.resolvedSpokenEditCommand(
            raw: "delete selection",
            settings: settings,
            targetApp: nil
        )
        XCTAssertNil(directCommand)

        settings.outputMode = .processed
        let processedCommand = await pipeline.resolvedSpokenEditCommand(
            raw: "delete selection",
            settings: settings,
            targetApp: nil
        )
        XCTAssertNil(processedCommand)
    }

    func testTranscriptionSanitizerRejectsEmptyAndPunctuation() {
        XCTAssertNil(TranscriptionSanitizer.prepare(""))
        XCTAssertNil(TranscriptionSanitizer.prepare("   "))
        XCTAssertNil(TranscriptionSanitizer.prepare("。。。"))
        XCTAssertNil(TranscriptionSanitizer.prepare("...!?"))
        XCTAssertNil(TranscriptionSanitizer.prepare("  -- ,, "))
    }

    func testTranscriptionSanitizerPreservesShortUtterancesWhenAudioEvidenceIsWeak() {
        let weakActivity = audioActivity(rms: 0.002)

        XCTAssertEqual(TranscriptionSanitizer.prepare("嗯", audioActivity: weakActivity), "嗯")
        XCTAssertEqual(TranscriptionSanitizer.prepare("Um.", audioActivity: weakActivity), "Um.")
        XCTAssertEqual(TranscriptionSanitizer.prepare(" OK ", audioActivity: weakActivity), "OK")
        XCTAssertEqual(TranscriptionSanitizer.prepare("yes", audioActivity: weakActivity), "yes")
        XCTAssertEqual(TranscriptionSanitizer.prepare("no", audioActivity: weakActivity), "no")
    }

    func testTranscriptionSanitizerDoesNotUsePhraseListsForWeakAudio() {
        let weakActivity = audioActivity(rms: 0.002)

        XCTAssertEqual(TranscriptionSanitizer.prepare("字幕志愿者:某某某", audioActivity: weakActivity), "字幕志愿者:某某某")
        XCTAssertEqual(TranscriptionSanitizer.prepare("请不吝点赞订阅转发打赏", audioActivity: weakActivity), "请不吝点赞订阅转发打赏")
        XCTAssertEqual(TranscriptionSanitizer.prepare("Thanks for watching!", audioActivity: weakActivity), "Thanks for watching!")
        XCTAssertEqual(TranscriptionSanitizer.prepare("Please subscribe to my channel", audioActivity: weakActivity), "Please subscribe to my channel")
        XCTAssertEqual(TranscriptionSanitizer.prepare("I'm sorry, I can't assist with that request.", audioActivity: weakActivity), "I'm sorry, I can't assist with that request.")
    }

    func testTranscriptionSanitizerAcceptsRealSpeech() {
        XCTAssertEqual(TranscriptionSanitizer.prepare("你好世界"), "你好世界")
        XCTAssertEqual(TranscriptionSanitizer.prepare("Hello world"), "Hello world")
        XCTAssertEqual(TranscriptionSanitizer.prepare("帮我整理一下这段话"), "帮我整理一下这段话")
        XCTAssertEqual(TranscriptionSanitizer.prepare("Write a function that adds two numbers"), "Write a function that adds two numbers")
    }

    func testTranscriptionSanitizerKeepsRepetitionWithoutWeakAudioEvidence() {
        XCTAssertEqual(
            TranscriptionSanitizer.prepare("帮我整理一下这段话 帮我整理一下这段话"),
            "帮我整理一下这段话 帮我整理一下这段话"
        )
        XCTAssertEqual(
            TranscriptionSanitizer.prepare("Write a short release note. Write a short release note."),
            "Write a short release note. Write a short release note."
        )
        XCTAssertEqual(TranscriptionSanitizer.prepare("yes yes"), "yes yes")
    }

    func testTranscriptionSanitizerCollapsesDuplicateOnlyForWeakAudio() {
        let weakActivity = audioActivity(rms: 0.002)

        XCTAssertEqual(
            TranscriptionSanitizer.prepare("帮我整理一下这段话 帮我整理一下这段话", audioActivity: weakActivity),
            "帮我整理一下这段话"
        )
        XCTAssertEqual(
            TranscriptionSanitizer.prepare(
                "Write a short release note. Write a short release note.",
                audioActivity: weakActivity
            ),
            "Write a short release note."
        )
    }

    func testTranscriptionPreviewKeepsSemanticCleanupForLLM() {
        XCTAssertEqual(
            TranscriptionSanitizer.previewText(
                "  open type no space cli comma all caps api key  ",
                inputLanguage: .english
            ),
            "open type no space cli comma all caps api key"
        )
        XCTAssertEqual(
            TranscriptionSanitizer.previewText(
                "项目符号 修登录 项目符号 跑回归",
                inputLanguage: .chinese
            ),
            "项目符号 修登录 项目符号 跑回归"
        )
    }

    func testTranscriptionPreviewHidesPunctuationOnlyArtifacts() {
        XCTAssertEqual(
            TranscriptionSanitizer.previewText("...", inputLanguage: .english),
            ""
        )
        XCTAssertEqual(
            TranscriptionSanitizer.previewText("。。。", inputLanguage: .chinese),
            ""
        )
    }

}
