import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterSession

@MainActor
final class VoiceSelectedRetentionTests: XCTestCase {
    func testAutomaticSelectedEditAndRestoreKeepFullVolatileReceiptWithoutHistoryOrLearning() async throws {
        let original = "  原文 e\u{301} 👩🏽‍💻\n" + String(repeating: "完整内容 🇸🇬。", count: 120) + "\n  "
        for mode in [TextProcessingMode.command, .selectionEdit(.custom("改礼貌一点"), spokenCommand: "改礼貌一点")] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.target.selectedText = original
            fixture.recipe.generatedText = "请您方便时同步进展。"
            let anchor = RetentionAnchor(target: fixture.target, text: "请您方便时同步进展。")
            fixture.output.delivery.anchor = anchor
            try await fixture.start()
            let history = try fixture.runtime.service(DataServices.history)
            let ordinary = InputRecord(rawText: "ordinary", processedText: "ordinary", wasProcessed: false)
            history.addRecord(ordinary)
            let historyURL = fixture.directory.appendingPathComponent("input_history.json")
            let persistedBefore = try Data(contentsOf: historyURL)
            let execution = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text("改礼貌一点"), mode: mode)
            try execution.start(intent)
            XCTAssertLessThan(fixture.target.context.selectedText?.count ?? 0, original.count)
            let applied = try await execution.waitForCompletion(intent.id)
            XCTAssertEqual(applied.deliveryStatus, .inserted)
            XCTAssertEqual(applied.text, "")
            XCTAssertEqual(applied.transcript, "")
            XCTAssertEqual(history.records.map(\.id), [ordinary.id])
            XCTAssertEqual(try Data(contentsOf: historyURL), persistedBefore)
            XCTAssertEqual(anchor.correctionReads, 0)
            XCTAssertTrue(fixture.correction.started.isEmpty)
            XCTAssertFalse(fixture.recipe.requests.first?.collectsDiagnostics ?? true)
            let outputs = try fixture.runtime.service(SessionServices.outputs)
            XCTAssertEqual(outputs.snapshot.selectionEditRestoration?.originalSelection, original)
            let restore = SessionIntent(input: .local, operation: .restoreSelectionEdit(operationID: intent.id))
            try execution.start(restore)
            let restored = try await execution.waitForCompletion(restore.id)
            XCTAssertEqual(restored.deliveryStatus, .inserted)
            XCTAssertEqual(restored.text, "")
            guard case .replaceAnchor(let written, _) = fixture.output.requests.last?.command else { return XCTFail("Restore did not replace its receipt") }
            XCTAssertEqual(written, original)
            XCTAssertNil(outputs.recent)
            XCTAssertEqual(outputs.snapshot, SessionOutputSnapshot())
            XCTAssertEqual(try Data(contentsOf: historyURL), persistedBefore)
            XCTAssertTrue(fixture.correction.started.isEmpty)
            XCTAssertEqual(anchor.correctionReads, 0)
            let cachedAfterRestore = try await execution.waitForCompletion(intent.id)
            XCTAssertEqual(cachedAfterRestore.text, "")

            fixture.target.selectedText = nil
            fixture.recipe.generatedText = nil
            let ordinaryAnchor = RetentionAnchor(target: fixture.target, text: "normal dictation")
            fixture.output.delivery.anchor = ordinaryAnchor
            let normal = SessionIntent(input: .text("normal dictation"), mode: .direct)
            try execution.start(normal)
            let completed = try await execution.waitForCompletion(normal.id)
            XCTAssertEqual(completed.text, "normal dictation")
            XCTAssertEqual(history.records.count, 2)
            XCTAssertEqual(history.records.first?.processedText, "normal dictation")
            XCTAssertEqual(fixture.correction.started, [normal.id])
            XCTAssertEqual(ordinaryAnchor.correctionReads, 1)
            let cachedAfterOrdinary = try await execution.waitForCompletion(intent.id)
            XCTAssertEqual(cachedAfterOrdinary.text, "")
            try await fixture.runtime.stop()
        }
    }

    func testCopiedSelectedCandidateHasNoPersistentHistoryOrGenericRecentText() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.target.selectedText = "private original"
        fixture.recipe.generatedText = "private candidate"
        fixture.output.delivery.effect = .clipboard
        fixture.output.delivery.confirmation = .clipboardValue
        try await fixture.start()
        let execution = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .text("rewrite"), mode: .command)
        try execution.start(intent)
        let completion = try await execution.waitForCompletion(intent.id)
        XCTAssertEqual(completion.deliveryStatus, .copied)
        XCTAssertEqual(completion.text, "")
        XCTAssertTrue(try fixture.runtime.service(DataServices.history).records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("input_history.json").path))
        XCTAssertEqual(try fixture.runtime.service(SessionServices.outputs).snapshot, SessionOutputSnapshot())
        XCTAssertTrue(fixture.correction.started.isEmpty)
        try await fixture.runtime.stop()
    }


}

@MainActor
private final class RetentionAnchor: OutputAnchor {
    let target: any OutputTargetLease
    let text: String
    var range: NSRange { NSRange(location: 0, length: text.utf16.count) }
    let expiresAt = Date().addingTimeInterval(15)
    let isCurrent = true
    var correctionReads = 0
    init(target: any OutputTargetLease, text: String) { self.target = target; self.text = text }
    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed? {
        correctionReads += 1
        return CorrectionCaptureSeed(observation: RetentionObservation(), insertedText: text, context: context)
    }
}

@MainActor
private final class RetentionObservation: CorrectionObservationSource {
    let isEligible = true
    let isFocused = true
    func readEditedText() -> String? { nil }
    func observe(_ callback: @escaping () -> Void) -> UUID? { nil }
    func removeObserver(_ id: UUID) {}
}
