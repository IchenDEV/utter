import XCTest
import UtterContracts
@testable import UtterSession

@MainActor
final class SessionControlTests: XCTestCase {
    func testApplyIsBoundToTheDisplayedProposalAndResumesExactlyOnce() async throws {
        let control = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
        let proposal = SelectionEditProposal(sessionID: UUID(), targetID: UUID(),
            originalSelection: "原文 👩🏽‍💻", recognizedInstruction: "改写", candidate: "候选 🧑‍🚀")
        let waiting = Task { try await control.waitForSelectionEditDecision(proposal) }
        for _ in 0..<100 where control.selectionEditProposal == nil { await Task.yield() }
        XCTAssertEqual(control.selectionEditProposal, proposal)
        XCTAssertFalse(control.applySelectionEdit(UUID()))
        XCTAssertTrue(control.applySelectionEdit(proposal.id))
        XCTAssertFalse(control.applySelectionEdit(proposal.id))
        try await waiting.value
        XCTAssertNil(control.selectionEditProposal)
    }

    func testCancellationAndEmptyCandidateNeverAuthorizeDelivery() async {
        let control = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
        let proposal = SelectionEditProposal(sessionID: UUID(), targetID: UUID(),
            originalSelection: "original", recognizedInstruction: "rewrite", candidate: "candidate")
        let waiting = Task { () -> Bool in
            do { try await control.waitForSelectionEditDecision(proposal); return true }
            catch { return false }
        }
        for _ in 0..<100 where control.selectionEditProposal == nil { await Task.yield() }
        control.revoke()
        XCTAssertFalse(control.applySelectionEdit(proposal.id))
        let allowed = await waiting.value
        XCTAssertFalse(allowed)
        XCTAssertNil(control.selectionEditProposal)
        let empty = SelectionEditProposal(sessionID: UUID(), targetID: UUID(),
            originalSelection: "original", recognizedInstruction: "rewrite", candidate: " \n ")
        let fresh = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
        do { try await fresh.waitForSelectionEditDecision(empty); XCTFail("Empty candidate entered review") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(fresh.selectionEditProposal)
    }

    func testDurationLimitFinalizesOnlyTheCurrentRecording() async throws {
        let control = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
        XCTAssertFalse(control.finalizeCapture(reason: .durationLimit))
        control.update(phase: .recording, transcript: "")
        let waiting = Task { try await control.waitForStop() }
        XCTAssertTrue(control.finalizeCapture(reason: .durationLimit))
        XCTAssertFalse(control.finalizeCapture(reason: .durationLimit))
        try await waiting.value
        let processing = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
        processing.update(phase: .processing, transcript: "done")
        XCTAssertFalse(processing.finalizeCapture(reason: .durationLimit))
        XCTAssertFalse(processing.isStopped)
        let retired = SessionControl(isCurrent: { false }, cancel: {}, update: { _, _ in })
        retired.update(phase: .recording, transcript: "")
        XCTAssertFalse(retired.finalizeCapture(reason: .durationLimit))
    }

    func testCancelledCaptureWaiterDrainsWithoutInventingAStop() async {
        let control = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
        var entered = false
        let waiter = Task { () -> Result<Void, Error> in
            entered = true
            do { try await control.waitForStop(); return .success(()) }
            catch { return .failure(error) }
        }
        while !entered { await Task.yield() }
        waiter.cancel()
        switch await waiter.value {
        case .success: XCTFail("Cancelled capture kept waiting")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(control.isStopped)
        control.stop()
        XCTAssertTrue(control.isStopped)
    }
}
