import XCTest
@testable import UtterKeyboardBridge

@MainActor
final class KeyboardSelectionBridgeTests: XCTestCase {
    func fixture() throws -> (SharedVoiceBridge, URL, KeyboardLease, UUID) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bridge = try SharedVoiceBridge(container: directory)
        let lease = KeyboardLease(generation: UUID(), documentID: UUID())
        let session = UUID()
        try bridge.renew(lease)
        var status = VoiceStatus(generation: lease.generation, phase: .processing)
        status.requestID = session; status.leaseID = lease.id; status.documentID = lease.documentID; status.selectionMode = true
        try bridge.publish(status)
        return (bridge, directory, lease, session)
    }

    func testSelectionStartCarriesFullOriginalAndConsumesOnce() throws {
        let (bridge, directory, lease, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = " \n" + String(repeating: "原文👨‍👩‍👧‍👦", count: 80) + "\n "
        let target = try KeyboardSelectionTarget(documentID: lease.documentID, selectedText: text, contextBefore: "前 ", contextAfter: " 后")
        let command = VoiceCommand(lease: lease, action: .startSelection, selectionTarget: target)
        try bridge.post(command)
        let taken = try bridge.take(command.id, generation: lease.generation)
        XCTAssertEqual(taken.version, 2)
        XCTAssertEqual(Array(taken.selectionTarget!.original.utf8), Array(text.utf8))
        XCTAssertThrowsError(try bridge.take(command.id, generation: lease.generation))
        XCTAssertEqual(VoiceCommand(lease: lease, action: .start).version, 1)
    }

    func testMissingSelectionFieldsAndWrongDocumentRejectBeforeCommandWrite() throws {
        let (bridge, directory, lease, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try KeyboardSelectionTarget(documentID: UUID(), selectedText: "原文", contextBefore: "", contextAfter: "")
        for command in [VoiceCommand(lease: lease, action: .startSelection), VoiceCommand(lease: lease, action: .startSelection, selectionTarget: target),
                        VoiceCommand(lease: lease, action: .applySelection), VoiceCommand(lease: lease, action: .restoreSelection)] {
            XCTAssertThrowsError(try bridge.post(command))
        }
        XCTAssertEqual(try bridge.pendingCommandIDs(), [])
    }

    func testReviewRoundTripPreservesEscapedTextAndClearsOnlyMatchingSession() throws {
        let (bridge, directory, lease, session) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try KeyboardSelectionTarget(documentID: lease.documentID, selectedText: String(repeating: "\u{1}", count: 8192), contextBefore: "", contextAfter: "")
        let review = KeyboardSelectionReview(id: UUID(), sessionID: session, lease: lease, target: target,
            recognizedInstruction: "改礼貌一点", candidate: "您好", expiresAt: target.expiresAt)
        try bridge.publishSelectionReview(review)
        XCTAssertEqual(try bridge.selectionReview(sessionID: session), review)
        XCTAssertNil(try bridge.selectionReview(sessionID: UUID()))
        try bridge.clearSelectionReview(sessionID: UUID())
        XCTAssertNotNil(try bridge.selectionReview(sessionID: session))
        try bridge.clearSelectionReview(sessionID: session)
        XCTAssertNil(try bridge.selectionReview(sessionID: session))
    }

    func testNativeOperationAndAcknowledgementAreBoundAndSingleUse() throws {
        let (bridge, directory, lease, session) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = KeyboardSelectionOperation(sessionID: session, lease: lease, kind: .apply, proposalID: UUID())
        try bridge.publishSelectionOperation(operation)
        let acknowledgement = KeyboardSelectionAcknowledgement(operation: operation, wrote: true, confirmed: true)
        XCTAssertThrowsError(try bridge.acknowledgeSelection(acknowledgement))
        XCTAssertEqual(try bridge.selectionOperation(sessionID: session), operation)
        try bridge.takeSelectionOperation(operation)
        XCTAssertNil(try bridge.selectionOperation(sessionID: session))
        XCTAssertThrowsError(try bridge.takeSelectionOperation(operation))
        let restoration = KeyboardSelectionRestoration(operationID: operation.id, sessionID: session, lease: lease, expiresAt: Date().addingTimeInterval(60))
        try bridge.acknowledgeSelection(acknowledgement, restoration: restoration)
        XCTAssertEqual(try bridge.selectionAcknowledgement(for: operation), acknowledgement)
        XCTAssertEqual(try bridge.selectionRestoration(), restoration)
        XCTAssertThrowsError(try bridge.acknowledgeSelection(acknowledgement))
        try bridge.clearSelectionOperation(operation)
        XCTAssertNil(try bridge.selectionAcknowledgement(for: operation))
        XCTAssertEqual(try bridge.selectionRestoration(), restoration)
        try bridge.clearSelectionRestoration(operationID: UUID())
        XCTAssertEqual(try bridge.selectionRestoration(), restoration)
        try bridge.clearSelectionRestoration(operationID: operation.id)
        XCTAssertNil(try bridge.selectionRestoration())
    }

    func testUncertainReadbackCannotGrantRestoration() throws {
        let (bridge, directory, lease, session) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = KeyboardSelectionOperation(sessionID: session, lease: lease, kind: .apply, proposalID: UUID())
        try bridge.publishSelectionOperation(operation); try bridge.takeSelectionOperation(operation)
        let uncertain = KeyboardSelectionAcknowledgement(operation: operation, wrote: true, confirmed: false)
        let restoration = KeyboardSelectionRestoration(operationID: operation.id, sessionID: session, lease: lease, expiresAt: Date().addingTimeInterval(60))
        XCTAssertThrowsError(try bridge.acknowledgeSelection(uncertain, restoration: restoration))
        XCTAssertNil(try bridge.selectionRestoration())
        try bridge.acknowledgeSelection(uncertain)
        XCTAssertEqual(try bridge.selectionAcknowledgement(for: operation)?.confirmed, false)
    }

    func testRevokedLeaseRejectsEffectAndLateAcknowledgement() throws {
        let (bridge, directory, lease, session) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = KeyboardSelectionOperation(sessionID: session, lease: lease, kind: .restore, restorationID: UUID())
        try bridge.publishSelectionOperation(operation); try bridge.takeSelectionOperation(operation)
        try bridge.revoke(lease.id)
        XCTAssertThrowsError(try bridge.acknowledgeSelection(KeyboardSelectionAcknowledgement(operation: operation, wrote: true, confirmed: true)))
        XCTAssertNil(try bridge.selectionAcknowledgement(for: operation))
    }

    func testWrongOperationAndImpossibleConfirmationCannotBeAcknowledged() throws {
        let (bridge, directory, lease, session) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = KeyboardSelectionOperation(sessionID: session, lease: lease, kind: .apply, proposalID: UUID())
        try bridge.publishSelectionOperation(operation); try bridge.takeSelectionOperation(operation)
        XCTAssertThrowsError(try bridge.acknowledgeSelection(KeyboardSelectionAcknowledgement(operation: operation, wrote: false, confirmed: true)))
        let wrong = KeyboardSelectionOperation(id: operation.id, sessionID: UUID(), lease: lease, kind: .apply, proposalID: operation.proposalID)
        XCTAssertThrowsError(try bridge.acknowledgeSelection(KeyboardSelectionAcknowledgement(operation: wrong, wrote: true, confirmed: true)))
        let future = KeyboardSelectionAcknowledgement(operation: operation, wrote: true, confirmed: true, createdAt: Date().addingTimeInterval(30))
        XCTAssertThrowsError(try bridge.acknowledgeSelection(future))
        XCTAssertNil(try bridge.selectionAcknowledgement(for: operation))
    }

    func testAbandonedPrivateCommandIsRetiredOnlyByItsBoundLease() throws {
        let (bridge, directory, lease, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try KeyboardSelectionTarget(documentID: lease.documentID, selectedText: "私密原文", contextBefore: "前", contextAfter: "后")
        let command = VoiceCommand(lease: lease, action: .startSelection, selectionTarget: target)
        try bridge.post(command)
        let wrong = KeyboardLease(id: lease.id, generation: lease.generation, documentID: UUID())
        XCTAssertThrowsError(try bridge.discardCommand(command.id, lease: wrong))
        XCTAssertEqual(try bridge.command(command.id).selectionTarget?.original, "私密原文")
        var renewed = lease; renewed.expiresAt = Date().addingTimeInterval(5)
        try bridge.discardCommand(command.id, lease: renewed)
        XCTAssertEqual(try bridge.pendingCommandIDs(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.root.appendingPathComponent("command-\(command.id).json").path))
        XCTAssertThrowsError(try bridge.take(command.id, generation: lease.generation))
        try bridge.discardCommand(command.id, lease: renewed)
    }

    func testPollingRetiresExpiredPrivateCommandBeforeAdmission() throws {
        let (bridge, directory, lease, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try KeyboardSelectionTarget(documentID: lease.documentID, selectedText: "私密原文", contextBefore: "前", contextAfter: "后")
        let command = VoiceCommand(lease: lease, action: .startSelection, selectionTarget: target)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        object["expiresAt"] = Date().addingTimeInterval(-1).timeIntervalSinceReferenceDate
        let url = bridge.root.appendingPathComponent("command-\(command.id).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        XCTAssertEqual(try bridge.pendingCommandIDs(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertThrowsError(try bridge.take(command.id, generation: lease.generation))
    }

    func testRejectedGenerationRetiresPrivateCommandAndPreventsReplay() throws {
        let (bridge, directory, lease, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try KeyboardSelectionTarget(documentID: lease.documentID, selectedText: "私密原文", contextBefore: "前", contextAfter: "后")
        let command = VoiceCommand(lease: lease, action: .startSelection, selectionTarget: target)
        try bridge.post(command)
        XCTAssertThrowsError(try bridge.take(command.id, generation: UUID()))
        XCTAssertEqual(try bridge.pendingCommandIDs(), [])
        try bridge.post(command)
        XCTAssertThrowsError(try bridge.take(command.id, generation: lease.generation))
        XCTAssertEqual(try bridge.pendingCommandIDs(), [])
    }

    func testExpiredPrivateReviewIsRemovedWhenBridgeReopens() throws {
        let (bridge, directory, lease, session) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try KeyboardSelectionTarget(documentID: lease.documentID, selectedText: "私密原文", contextBefore: "前", contextAfter: "后")
        let review = KeyboardSelectionReview(id: UUID(), sessionID: session, lease: lease, target: target,
            recognizedInstruction: "私密命令", candidate: "完整结果", expiresAt: Date().addingTimeInterval(-1))
        let url = bridge.root.appendingPathComponent("selection-review.json")
        try JSONEncoder().encode(review).write(to: url)
        _ = try SharedVoiceBridge(container: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testTerminalStatusRemovesPrivateReviewWithoutWaitingForJobCleanup() throws {
        let (bridge, directory, lease, session) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try KeyboardSelectionTarget(documentID: lease.documentID, selectedText: "私密原文", contextBefore: "前", contextAfter: "后")
        let review = KeyboardSelectionReview(id: UUID(), sessionID: session, lease: lease, target: target,
            recognizedInstruction: "私密命令", candidate: "完整结果", expiresAt: target.expiresAt)
        try bridge.publishSelectionReview(review)
        try bridge.publish(VoiceStatus(generation: lease.generation, phase: .ready))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.root.appendingPathComponent("selection-review.json").path))
    }
}
