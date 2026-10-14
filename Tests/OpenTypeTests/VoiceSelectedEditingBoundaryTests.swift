import Foundation
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterSession

@MainActor
final class VoiceSelectedEditingBoundaryTests: XCTestCase {
    func testNaturalSelectedInstructionUsesOneRecordingAndReviewWithoutScreenOrAction() async throws {
        for apply in [false, true] {
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
            let intent = SessionIntent(input: .local, mode: .command)
            try execution.start(intent)
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while execution.snapshot.phase != .recording, execution.snapshot.isBusy, ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertTrue(execution.requestStop(intent.id, at: nil))
            let proposal = try await review(in: execution)
            XCTAssertEqual(proposal.sessionID, intent.id)
            XCTAssertEqual(proposal.recognizedInstruction, "改礼貌一点")
            XCTAssertEqual(proposal.originalSelection, "请同步进展。 e\u{301} 👩🏽‍💻")
            XCTAssertEqual(proposal.candidate, "请您方便时同步进展。")
            XCTAssertEqual(fixture.capture.requests.count, 1)
            XCTAssertEqual(fixture.speechRequests.count, 1)
            XCTAssertTrue(fixture.capture.recording.closed)
            XCTAssertEqual(fixture.recipeCreations, ["mode.edit"])
            XCTAssertTrue(fixture.recipe.resolutionContexts.isEmpty)
            XCTAssertTrue(fixture.screen.requests.isEmpty)
            XCTAssertTrue(fixture.output.requests.isEmpty)
            if apply {
                XCTAssertTrue(execution.applySelectionEdit(sessionID: intent.id, proposalID: proposal.id))
                XCTAssertFalse(execution.applySelectionEdit(sessionID: intent.id, proposalID: proposal.id))
                _ = try await execution.waitForCompletion(intent.id)
                guard case .replaceSelection("请您方便时同步进展。") = fixture.output.requests.first?.command else {
                    return XCTFail("Selected instruction did not use the reviewed replacement")
                }
                XCTAssertEqual(fixture.output.requests.count, 1)
            } else {
                execution.cancel(intent.id)
                do { _ = try await execution.waitForCompletion(intent.id); XCTFail("Cancelled edit completed") }
                catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertTrue(fixture.output.requests.isEmpty)
            }
            try await fixture.runtime.stop()
        }
    }

    func testSelectedCommandKeepsFullInstructionAndExplicitSelectionEditNeverCapturesScreen() async throws {
        let instruction = "改礼貌一点，" + String(repeating: "保留原来的细节。", count: 120) + "结尾保留 🇸🇬。"
        for mode in [TextProcessingMode.command, .selectionEdit(.custom(instruction), spokenCommand: instruction)] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.defaults.set(true, forKey: "useScreenContext")
            fixture.target.selectedText = "完整原文 👩🏽‍💻\n" + String(repeating: "保留细节。", count: 200)
            fixture.recipe.generatedText = "完整候选 🇸🇬"
            try await fixture.start()
            let execution = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text(instruction), mode: mode)
            try execution.start(intent)
            let proposal = try await review(in: execution)
            XCTAssertEqual(proposal.recognizedInstruction, instruction)
            XCTAssertEqual(fixture.recipe.requests.first?.text, fixture.target.selectedText)
            XCTAssertEqual(fixture.recipe.requests.first?.mode, .selectionEdit(.custom(instruction), spokenCommand: instruction))
            XCTAssertEqual(fixture.recipeCreations, ["mode.edit"])
            XCTAssertEqual(fixture.recipe.requests.first?.screenContext, "")
            XCTAssertNil(fixture.recipe.requests.first?.screenImage)
            XCTAssertTrue(fixture.screen.requests.isEmpty)
            execution.cancel(intent.id)
            do { _ = try await execution.waitForCompletion(intent.id); XCTFail("Cancelled edit completed") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertTrue(fixture.output.requests.isEmpty)
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

    private func review(in execution: any SessionExecutionService) async throws -> SelectionEditProposal {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while execution.snapshot.selectionEditProposal == nil, execution.snapshot.isBusy, ContinuousClock.now < deadline { await Task.yield() }
        return try XCTUnwrap(execution.snapshot.selectionEditProposal)
    }
}
