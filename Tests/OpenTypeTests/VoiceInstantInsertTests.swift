import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterSession

@MainActor
final class VoiceInstantInsertTests: XCTestCase {
    func testInitialTextCommitsBeforeBackgroundFormattingAndNewInputDrainsFormatter() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.defaults.set(true, forKey: "enableInstantInsert")
        fixture.recipe.holdFormatting = true
        fixture.output.delivery.anchor = EditingAnchor(target: fixture.target, text: "Quick text")
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        let history = try fixture.runtime.service(DataServices.history)
        let outputs = try fixture.runtime.service(SessionServices.outputs)
        let first = SessionIntent(input: .text("Quick text"), mode: .formatting)
        try driver.start(first)
        _ = try await driver.waitForCompletion(first.id)
        while !fixture.recipe.formatting { await Task.yield() }
        XCTAssertEqual(history.records.map(\.id), [first.id])
        XCTAssertEqual(history.records.first?.processedText, "Quick text")
        XCTAssertEqual(history.records.first?.wasProcessed, false)
        XCTAssertEqual(outputs.snapshot.pending?.state, .formatting)
        fixture.output.delivery.anchor = nil
        let next = SessionIntent(input: .text("Next text"), mode: .direct)
        try driver.start(next)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(driver.snapshot.isBusy)
        XCTAssertEqual(fixture.output.requests.count, 1)
        fixture.recipe.releaseFormatting()
        _ = try await driver.waitForCompletion(next.id)
        XCTAssertEqual(history.records.map(\.processedText), ["Next text", "Quick text"])
        XCTAssertNil(outputs.snapshot.pending)
        XCTAssertEqual(outputs.snapshot.recentText, "Next text")
        try await fixture.runtime.stop()
    }

    func testFormatterBecomesReadyWithoutWritingAnotherHistoryRecordOrReplacingDocument() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.defaults.set(true, forKey: "enableInstantInsert")
        fixture.output.delivery.anchor = EditingAnchor(target: fixture.target, text: "Quick text")
        try await fixture.start()
        let driver = try fixture.runtime.service(SessionServices.execution)
        let outputs = try fixture.runtime.service(SessionServices.outputs)
        let intent = SessionIntent(input: .text("Quick text"), mode: .formatting)
        try driver.start(intent)
        _ = try await driver.waitForCompletion(intent.id)
        while outputs.snapshot.pending?.state == .formatting { await Task.yield() }
        XCTAssertEqual(outputs.snapshot.pending?.state, .ready)
        XCTAssertEqual(outputs.snapshot.pending?.formattedText, "Quick text Formatted.")
        XCTAssertEqual(try fixture.runtime.service(DataServices.history).records.map(\.processedText), ["Quick text"])
        XCTAssertEqual(fixture.output.requests.count, 1)
        try await fixture.runtime.stop()
    }
}
