import Foundation
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterSession

@MainActor
final class VoiceSelectedEditingBoundaryTests: XCTestCase {
    func testNaturalSelectedInstructionAutomaticallyWritesOnceAfterOneRecordingWithoutScreenOrAction() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.defaults.set(true, forKey: "useScreenContext")
        fixture.target.selectedText = "请同步进展。 e\u{301} 👩🏽‍💻"
        fixture.engine.transcript = "改礼貌一点"
        fixture.recipe.resolution = .command(.deleteSelection)
        fixture.recipe.generatedText = "请您方便时同步进展。"
        fixture.screen.snapshot = ScreenContextSnapshot(text: "", image: nil, status: .permissionDenied)
        try await fixture.start()
        let execution = try fixture.runtime.service(SessionServices.execution)
        var sawProposal = false
        let observer = execution.observe { sawProposal = sawProposal || $0.selectionEditProposal != nil }
        defer { execution.removeObserver(observer) }
        let intent = SessionIntent(input: .local, mode: .command)
        try execution.start(intent)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while execution.snapshot.phase != .recording, execution.snapshot.isBusy, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(execution.snapshot.isSelectionEditing)
        XCTAssertTrue(execution.requestStop(intent.id, at: nil))
        let result = try await execution.waitForCompletion(intent.id)
        XCTAssertEqual(result.deliveryStatus, .inserted)
        XCTAssertFalse(sawProposal)
        XCTAssertEqual(fixture.capture.requests.count, 1)
        XCTAssertEqual(fixture.speechRequests.count, 1)
        XCTAssertTrue(fixture.capture.recording.closed)
        XCTAssertEqual(fixture.recipeCreations, ["mode.edit"])
        XCTAssertEqual(fixture.recipe.requests.first?.mode, .selectionEdit(.custom("改礼貌一点"), spokenCommand: "改礼貌一点"))
        XCTAssertTrue(fixture.recipe.resolutionContexts.isEmpty)
        XCTAssertTrue(fixture.screen.requests.isEmpty)
        guard case .replaceSelection("请您方便时同步进展。") = fixture.output.requests.first?.command else {
            return XCTFail("Selected instruction did not use automatic replacement")
        }
        XCTAssertEqual(fixture.output.requests.count, 1)
        XCTAssertFalse(execution.applySelectionEdit(sessionID: intent.id, proposalID: UUID()))
        XCTAssertEqual(fixture.output.requests.count, 1)
        try await fixture.runtime.stop()
    }

    func testAutomaticSelectedCommandKeepsFullInstructionAndExplicitSelectionEditNeverCapturesScreen() async throws {
        let instruction = "改礼貌一点，" + String(repeating: "保留原来的细节。", count: 120) + "结尾保留 🇸🇬。"
        for mode in [TextProcessingMode.command, .selectionEdit(.custom(instruction), spokenCommand: instruction)] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.defaults.set(true, forKey: "useScreenContext")
            let original = "完整原文 👩🏽‍💻\n" + String(repeating: "保留细节。", count: 200)
            fixture.target.selectedText = original
            fixture.recipe.generatedText = "完整候选 🇸🇬"
            try await fixture.start()
            let execution = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text(instruction), mode: mode)
            try execution.start(intent)
            _ = try await execution.waitForCompletion(intent.id)
            XCTAssertEqual(fixture.recipe.requests.first?.text, original)
            XCTAssertEqual(fixture.recipe.requests.first?.mode, .selectionEdit(.custom(instruction), spokenCommand: instruction))
            XCTAssertEqual(fixture.recipeCreations, ["mode.edit"])
            XCTAssertEqual(fixture.recipe.requests.first?.screenContext, "")
            XCTAssertNil(fixture.recipe.requests.first?.screenImage)
            XCTAssertTrue(fixture.screen.requests.isEmpty)
            XCTAssertNil(execution.snapshot.selectionEditProposal)
            guard case .replaceSelection("完整候选 🇸🇬") = fixture.output.requests.first?.command else { return XCTFail("Missing automatic replacement") }
            XCTAssertEqual(fixture.output.requests.count, 1)
            try await fixture.runtime.stop()
        }
    }

    func testEmptyDeleteActionAndFailedGenerationNeverOfferApplyOrWriteSelection() async throws {
        let outputs: [String?] = [" \n ", "{\"final_text\":\"\"}", "{\"action\":\"delete_selection\",\"confidence\":1}", nil]
        for output in outputs {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.target.selectedText = "原文 👩🏽‍💻"
            fixture.recipe.resolution = .command(.deleteSelection)
            fixture.recipe.generatedText = output
            if output == nil { fixture.recipe.failure = GenerationServiceError.modelUnavailable }
            try await fixture.start()
            let execution = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text("删除选区"), mode: .command)
            try execution.start(intent)
            do { _ = try await execution.waitForCompletion(intent.id); XCTFail("Invalid selected result was accepted") }
            catch {}
            XCTAssertEqual(execution.snapshot.phase, .failed)
            XCTAssertNil(execution.snapshot.selectionEditProposal)
            XCTAssertFalse(execution.applySelectionEdit(sessionID: intent.id, proposalID: UUID()))
            XCTAssertEqual(fixture.target.selectedText, "原文 👩🏽‍💻")
            XCTAssertEqual(fixture.recipeCreations, ["mode.edit"])
            XCTAssertTrue(fixture.recipe.resolutionContexts.isEmpty)
            XCTAssertTrue(fixture.output.requests.isEmpty)
            XCTAssertTrue(fixture.screen.requests.isEmpty)
            try await fixture.runtime.stop()
        }
    }

    func testUnselectedLegacyReplyAndOrdinaryDictationKeepTheirExistingRoutes() async throws {
        for mode in [TextProcessingMode.command, .direct, .formatting, .translation(.english)] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.defaults.set(false, forKey: "useScreenContext")
            fixture.defaults.set(false, forKey: "enableInstantInsert")
            if mode != .command { fixture.target.selectedText = "Existing selection" }
            try await fixture.start()
            let execution = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text("帮我回复这封邮件"), mode: mode)
            try execution.start(intent)
            _ = try await execution.waitForCompletion(intent.id)
            XCTAssertEqual(fixture.recipe.requests.first?.mode, mode)
            XCTAssertNil(execution.snapshot.selectionEditProposal)
            XCTAssertEqual(fixture.screen.requests.count, mode == .command ? 1 : 0)
            guard case .insert = fixture.output.requests.first?.command else { return XCTFail("Ordinary mode changed output route") }
            XCTAssertEqual(fixture.output.requests.count, 1)
            try await fixture.runtime.stop()
        }
    }


}
