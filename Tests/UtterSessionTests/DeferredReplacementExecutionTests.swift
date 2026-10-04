import Foundation
import XCTest
import UtterContracts
import UtterData
@testable import UtterSession

@MainActor
final class DeferredReplacementExecutionTests: XCTestCase {
    func testAcceptedReplacementUpdatesItsRecordDespiteNewerHistory() async throws {
        let fixture = try ReplacementFixture()
        defer { fixture.remove() }
        let original = InputRecord(id: fixture.recordID, date: Date(), rawText: "Raw", processedText: "Quick", wasProcessed: false)
        let other = InputRecord(rawText: "Other", processedText: "Other", wasProcessed: false)
        fixture.history.addRecord(original)
        fixture.history.addRecord(other)
        let driver = fixture.driver()
        let intent = SessionIntent(input: .local, operation: .applyReplacement(fixture.pending.id))
        var notifications = 0
        _ = fixture.history.observe {
            XCTAssertEqual(driver.snapshot.phase, .completed)
            XCTAssertFalse(driver.snapshot.isBusy)
            XCTAssertEqual(fixture.history.records.last?.processedText, "Formatted")
            notifications += 1
        }
        try driver.start(intent)
        let result = try await driver.waitForCompletion(intent.id)
        XCTAssertEqual(result.text, "Formatted")
        XCTAssertEqual(fixture.history.records.map(\.id), [other.id, original.id])
        XCTAssertEqual(fixture.history.records.first?.processedText, "Other")
        XCTAssertEqual(fixture.history.records.last?.processedText, "Formatted")
        XCTAssertEqual(fixture.output.requests.first?.id, intent.id)
        XCTAssertEqual(notifications, 1)
        await driver.close()
    }

    func testExpiredAnchorCopiesWithoutChangingOriginalHistory() async throws {
        let fixture = try ReplacementFixture(expired: true)
        defer { fixture.remove() }
        fixture.history.addRecord(InputRecord(id: fixture.recordID, date: Date(), rawText: "Raw", processedText: "Quick", wasProcessed: false))
        let driver = fixture.driver()
        let intent = SessionIntent(input: .local, operation: .applyReplacement(fixture.pending.id))
        try driver.start(intent)
        _ = try await driver.waitForCompletion(intent.id)
        guard case .clipboard("Formatted") = fixture.output.requests.first?.command else { return XCTFail("Expired replacement was not copied") }
        XCTAssertEqual(fixture.history.records.map(\.processedText), ["Quick"])
        await driver.close()
    }

    func testReservedReplacementCannotDeliverAfterItsPendingIDChanges() async throws {
        let fixture = try ReplacementFixture()
        defer { fixture.remove() }
        let driver = fixture.driver()
        let intent = SessionIntent(input: .local, operation: .applyReplacement(fixture.pending.id))
        try driver.reserve(intent)
        fixture.outputs.clearPending(fixture.pending.id)
        try driver.activate(intent.id)
        do { _ = try await driver.waitForCompletion(intent.id); XCTFail("Retired pending replacement committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertTrue(fixture.history.records.isEmpty)
        await driver.close()
    }
}

@MainActor
private final class ReplacementFixture: SessionWorkflowFactory {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recordID = UUID()
    let notifications = StateNotifications()
    let target = ReplacementTarget()
    let output = ReplacementOutput()
    let outputs: SessionOutputState
    let history: HistoryStore
    let pending: DeferredReplacement
    init(expired: Bool = false) throws {
        outputs = SessionOutputState(notifications: notifications)
        history = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in }, notifications: notifications)
        let anchor = ReplacementAnchor(target: target)
        outputs.remember(SessionCompletion(transcript: "Raw", text: "Quick", acceptance: .delivery(
            DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste, anchor: anchor))), recordID: recordID)
        var row = DeferredReplacement(historyRecordID: recordID, rawText: "Raw", insertedText: "Quick",
            targetPID: target.processIdentifier, targetBundleIdentifier: target.context.bundleIdentifier,
            message: "Ready", createdAt: Date().addingTimeInterval(expired ? -20 : 0))
        row.state = .ready; row.formattedText = "Formatted"
        pending = row
        XCTAssertTrue(outputs.installPending(row, anchor: anchor))
    }
    func make(_ intent: SessionIntent) throws -> any SessionJob {
        try DeferredReplacementJob(id: pending.id, outputs: outputs, output: output,
            access: ReplacementAccess(), target: target, operationID: intent.id, authorize: {})
    }
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {}
    func driver() -> SessionDriver { SessionDriver(workflows: self, history: history, notifications: notifications) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private struct ReplacementAccess: ModelResourceAccess {
    func withAccess<Value>(_ operation: () async throws -> Value) async throws -> Value { try await operation() }
}
@MainActor
private final class ReplacementOutput: OutputService, PreparedDelivery {
    var requests: [DeliveryRequest] = []
    var receipt: DeliveryReceipt?
    func prepare(_ request: DeliveryRequest, isSessionCurrent: @escaping () -> Bool) throws -> any PreparedDelivery {
        guard isSessionCurrent() else { throw CancellationError() }
        requests.append(request); return self
    }
    func commit() async -> DeliveryReceipt {
        let result = DeliveryReceipt(operationID: requests.last!.id, disposition: .accepted, effect: .paste)
        receipt = result; return result
    }
    func close() async {}
}
@MainActor
private final class ReplacementTarget: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 1
    let context = InputContext(appName: "Editor", bundleIdentifier: "fixture.editor", outputMode: .processed, inputLanguage: .english, source: .menuBar)
    let isValid = true
    let isCurrent = true
}
@MainActor
private final class ReplacementAnchor: OutputAnchor {
    let target: any OutputTargetLease
    let range = NSRange(location: 0, length: 5)
    let text = "Quick"
    let expiresAt = Date().addingTimeInterval(15)
    let isCurrent = true
    init(target: any OutputTargetLease) { self.target = target }
    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed? { nil }
}
