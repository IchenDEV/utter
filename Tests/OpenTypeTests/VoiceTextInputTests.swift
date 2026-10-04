import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterSession

@MainActor
final class VoiceTextInputTests: XCTestCase {
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
        _ = try await driver.waitForCompletion(intent.id)
        XCTAssertEqual(fixture.recipe.requests.first?.text, selected)
        XCTAssertEqual(fixture.recipe.requests.first?.mode, mode)
        guard case .replaceSelection = fixture.output.requests.first?.command else { return XCTFail("Selection edit did not replace selection") }
        XCTAssertTrue(fixture.speechRequests.isEmpty)
        try await fixture.runtime.stop()
    }
}
