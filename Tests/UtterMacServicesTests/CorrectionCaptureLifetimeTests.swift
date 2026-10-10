import Foundation
import XCTest
import UtterContracts
import UtterData
@testable import UtterMacServices

@MainActor
final class CorrectionCaptureLifetimeTests: XCTestCase {
    private func fixture() -> (CorrectionCaptureService, CorrectionSourceFixture, () -> [LearnedCorrectionCandidate], () -> [(UUID, String)]) {
        let source = CorrectionSourceFixture()
        var learned: [LearnedCorrectionCandidate] = []
        var updates: [(UUID, String)] = []
        let service = CorrectionCaptureService(
            enabled: { true }, classification: BuiltinCorrectionClassification(),
            learn: { learned.append($0) }, updateHistory: { updates.append(($0, $1)) },
            log: Log(service: CorrectionTestDiagnostics())
        )
        return (service, source, { learned }, { updates })
    }

    private func seed(_ source: CorrectionSourceFixture) -> CorrectionCaptureSeed {
        CorrectionCaptureSeed(observation: source, insertedText: "请联系张三", context: InputContext(
            outputMode: .processed, inputLanguage: .chinese, source: .menuBar
        ))
    }

    func testFinalCorrectionUpdatesOnlyItsRecordAndLearnsOnce() async {
        let (service, source, learned, updates) = fixture()
        let recordID = UUID()
        service.start(seed: seed(source), recordID: recordID)
        source.edited = "请联系章三"
        service.finishCurrentSession()
        service.finishCurrentSession()
        XCTAssertEqual(updates().count, 1)
        XCTAssertEqual(updates().first?.0, recordID)
        XCTAssertEqual(learned().count, 1)
        XCTAssertEqual(learned().first?.sourceRecordID, recordID)
        XCTAssertEqual(source.removals, 1)
        await service.close()
    }

    func testNewlySecureFieldIsExcludedBeforeReadingAndLearning() async {
        let (service, source, learned, updates) = fixture()
        service.start(seed: seed(source), recordID: UUID())
        source.edited = "请联系章三"
        source.isEligible = false
        service.finishCurrentSession()
        XCTAssertEqual(source.reads, 0)
        XCTAssertTrue(learned().isEmpty)
        XCTAssertTrue(updates().isEmpty)
        await service.close()
    }

    func testRevocationRemovesObservationAndRejectsQueuedCallbacksAndRestarts() async {
        let (service, source, learned, updates) = fixture()
        service.start(seed: seed(source), recordID: UUID())
        let queued = source.callback
        service.revoke()
        source.edited = "请联系章三"
        queued?()
        service.finishCurrentSession()
        service.start(seed: seed(source), recordID: UUID())
        await service.close()
        XCTAssertEqual(source.subscriptions, 1)
        XCTAssertEqual(source.removals, 1)
        XCTAssertTrue(learned().isEmpty)
        XCTAssertTrue(updates().isEmpty)
    }
}

@MainActor
private final class CorrectionSourceFixture: CorrectionObservationSource {
    var isEligible = true
    var isFocused = true
    var edited = "请联系张三"
    var callback: (() -> Void)?
    var subscriptions = 0
    var removals = 0
    var reads = 0
    func readEditedText() -> String? { reads += 1; return edited }
    func observe(_ callback: @escaping () -> Void) -> UUID? {
        subscriptions += 1
        self.callback = callback
        return UUID()
    }
    func removeObserver(_ id: UUID) { removals += 1; callback = nil }
}

private struct CorrectionTestDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
