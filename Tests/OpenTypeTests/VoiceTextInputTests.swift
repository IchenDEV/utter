import UtterPresentationContracts
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterSession

@MainActor
final class VoiceTextInputTests: XCTestCase {
    func testAuthorizedClientWithoutDesktopTargetReturnsTextWithoutDesktopEffects() async throws {
        for instant in [false, true] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.targetAvailable = false
            fixture.defaults.set(false, forKey: "allowClipboardPaste")
            fixture.defaults.set(instant, forKey: "enableInstantInsert")
            try await fixture.start()
            let client = IntegrationClient.localCLI(executablePath: "/fixture/cli")
            try fixture.runtime.service(IntegrationServices.clients).approve(client)
            let driver = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(clientID: client.id, input: .text("Synthetic dictation"), mode: .formatting)
            try driver.start(intent)
            let result = try await driver.waitForCompletion(intent.id)
            XCTAssertEqual(result.phase, .completed)
            XCTAssertEqual(result.text, "Synthetic dictation Formatted.")
            XCTAssertEqual(fixture.recipe.requests.count, 1)
            XCTAssertTrue(fixture.screen.requests.isEmpty)
            XCTAssertTrue(fixture.output.requests.isEmpty)
            try await fixture.runtime.stop()
        }
    }

    func testCreatedTextJobFreezesMemoryBeforeHistoryChanges() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let history = try fixture.runtime.service(DataServices.history)
        history.addRecord(InputRecord(rawText: "Original memory", processedText: "Original memory", wasProcessed: false))
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .text("Current text"), mode: .formatting)
        try driver.reserve(intent)
        history.clearAll()
        history.addRecord(InputRecord(rawText: "Later memory", processedText: "Later memory", wasProcessed: false))
        try driver.activate(intent.id)
        _ = try await driver.waitForCompletion(intent.id)
        XCTAssertTrue(fixture.recipe.requests.first?.memoryContext.contains("Original memory") == true)
        XCTAssertFalse(fixture.recipe.requests.first?.memoryContext.contains("Later memory") == true)
        try await fixture.runtime.stop()
    }

    func testTranslationCanRunWithNoSpeechProviderInstalled() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.defaults.set("unmounted.speech", forKey: "speechEngine")
        try await fixture.start()
        let providers = try fixture.runtime.service(SpeechServices.providers)
        if let registry = providers as? ProviderRegistry<SpeechProviderRequest, any SpeechEngine> { registry.close() }
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .text("Translate this paragraph"), mode: .translation(.english))
        try driver.start(intent)
        _ = try await driver.waitForCompletion(intent.id)
        XCTAssertEqual(fixture.recipe.requests.first?.mode, .translation(.english))
        XCTAssertTrue(fixture.speechRequests.isEmpty)
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        XCTAssertEqual(fixture.output.requests.count, 1)
        try await fixture.runtime.stop()
    }

    func testExplicitSelectionEditProcessesFullSelectionAndUsesSelectionReplacement() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        let selected = String(repeating: "Full selection. ", count: 100)
        fixture.target.selectedText = selected
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        let mode = TextProcessingMode.selectionEdit(.concise, spokenCommand: "Make concise")
        let intent = SessionIntent(input: .text("Make concise"), mode: mode)
        try driver.start(intent)
        let proposal = try await review(in: driver)
        XCTAssertEqual(proposal.originalSelection, selected)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertTrue(driver.applySelectionEdit(sessionID: intent.id, proposalID: proposal.id))
        XCTAssertFalse(driver.applySelectionEdit(sessionID: intent.id, proposalID: proposal.id))
        _ = try await driver.waitForCompletion(intent.id)
        XCTAssertEqual(fixture.recipe.requests.first?.text, selected)
        XCTAssertEqual(fixture.recipe.requests.first?.mode, mode)
        guard case .replaceSelection = fixture.output.requests.first?.command else { return XCTFail("Selection edit did not replace selection") }
        XCTAssertTrue(fixture.speechRequests.isEmpty)
        XCTAssertEqual(fixture.output.requests.count, 1)
        try await fixture.runtime.stop()
    }

    func testSelectionReviewCancellationAndStaleSelectionNeverPrepareHostOrClipboardWrites() async throws {
        for cancel in [false, true] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.target.selectedText = "原文 e\u{301} 👩🏽‍💻\n第二行"
            try await fixture.start()
            let driver = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text("Make concise"), mode: .selectionEdit(.concise, spokenCommand: "Make concise"))
            try driver.start(intent)
            let proposal = try await review(in: driver)
            XCTAssertEqual(proposal.originalSelection, "原文 e\u{301} 👩🏽‍💻\n第二行")
            XCTAssertTrue(fixture.output.requests.isEmpty)
            if cancel { driver.cancel(intent.id) }
            else {
                fixture.target.selectedText = "用户后续输入 🇸🇬"
                XCTAssertTrue(driver.applySelectionEdit(sessionID: intent.id, proposalID: proposal.id))
            }
            do { _ = try await driver.waitForCompletion(intent.id); XCTFail("Cancelled or stale edit delivered") }
            catch {
                if cancel { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertEqual(error as? DeliveryError, .invalidTarget) }
            }
            XCTAssertTrue(fixture.output.requests.isEmpty)
            XCTAssertNil(driver.snapshot.selectionEditProposal)
            XCTAssertTrue(fixture.capture.requests.isEmpty)
            try await fixture.runtime.stop()
        }
    }

    func testFailedAndEmptySelectionGenerationHasNoReviewAndLeavesTheOriginalIntact() async throws {
        for fails in [false, true] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.target.selectedText = "original 👩🏽‍💻"
            if fails { fixture.recipe.failure = GenerationServiceError.modelUnavailable }
            else { fixture.recipe.generatedText = " \n " }
            try await fixture.start()
            let driver = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text("rewrite"), mode: .selectionEdit(.concise, spokenCommand: "rewrite"))
            try driver.start(intent)
            do { _ = try await driver.waitForCompletion(intent.id); XCTFail("Failed model was accepted") }
            catch {}
            XCTAssertEqual(driver.snapshot.phase, .failed)
            XCTAssertNil(driver.snapshot.selectionEditProposal)
            XCTAssertEqual(fixture.target.selectedText, "original 👩🏽‍💻")
            XCTAssertTrue(fixture.output.requests.isEmpty)
            try await fixture.runtime.stop()
        }
    }

    func testRemoteSelectionPreflightDoesNotStartCaptureOrProcessingAndRechecksTheProvider() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.defaults.set(true, forKey: "useRemoteLLM")
        fixture.defaults.set("https://model.example.test/v1", forKey: "remoteBaseURL")
        fixture.target.selectedText = "private selection 👩🏽‍💻"
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local, mode: .selectionEdit(.concise, spokenCommand: "rewrite"))
        try driver.start(intent)
        XCTAssertEqual(driver.snapshot.remoteDisclosure?.providerHost, "model.example.test")
        XCTAssertEqual(driver.snapshot.remoteDisclosure?.selectedText, "private selection 👩🏽‍💻")
        XCTAssertTrue(fixture.recipe.requests.isEmpty)
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        try fixture.runtime.service(DataServices.settings).update { $0.remoteBaseURL = "https://changed.example.test/v1" }
        XCTAssertThrowsError(try driver.authorizeRemoteDisclosure(intent.id))
        XCTAssertTrue(fixture.recipe.requests.isEmpty)
        XCTAssertTrue(fixture.capture.requests.isEmpty)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertFalse(driver.snapshot.isBusy)
        try await fixture.runtime.stop()
    }

    private func review(in driver: any SessionExecutionService) async throws -> SelectionEditProposal {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while driver.snapshot.selectionEditProposal == nil, driver.snapshot.isBusy, ContinuousClock.now < deadline {
            await Task.yield()
        }
        return try XCTUnwrap(driver.snapshot.selectionEditProposal)
    }
}
