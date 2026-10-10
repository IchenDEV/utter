import Foundation
import XCTest
import UtterContracts
@testable import UtterSession

@MainActor
final class CopySessionJobTests: XCTestCase {
    func testExplicitCopyUsesOneSharedTransactionAndNeverClaimsInsertion() async throws {
        let output = CopyOutput()
        let id = UUID()
        let job = try CopySessionJob(id: id, text: "  preserved candidate  ", output: output)
        let control = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
        let completion = try await job.run(control: control)
        XCTAssertEqual(output.requests.count, 1)
        XCTAssertEqual(output.requests.first?.id, id)
        guard case .clipboard("  preserved candidate  ") = output.requests.first?.command else {
            return XCTFail("Explicit copy transformed or inserted the candidate")
        }
        XCTAssertNil(output.requests.first?.target)
        XCTAssertEqual(completion.acceptance.deliveryStatus, .copied)
        XCTAssertNil(completion.record)
        XCTAssertNil(completion.historyReplacement)
        guard case .preserve = completion.outputMutation else { return XCTFail("Copy retired a prior insertion anchor") }
        await job.close()
    }

    func testRevokedCopyHasNoEffectsAndEmptyCopyCannotReserve() async throws {
        let output = CopyOutput()
        XCTAssertThrowsError(try CopySessionJob(id: UUID(), text: " \n ", output: output))
        let id = UUID()
        let job = try CopySessionJob(id: id, text: "candidate", output: output)
        job.revoke()
        let control = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
        do { _ = try await job.run(control: control); XCTFail("A revoked copy committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(output.requests.isEmpty)
    }
}

@MainActor
private final class CopyOutput: OutputService, PreparedDelivery {
    var requests: [DeliveryRequest] = []
    var receipt: DeliveryReceipt?
    func prepare(_ request: DeliveryRequest, isSessionCurrent: @escaping () -> Bool) throws -> any PreparedDelivery {
        guard isSessionCurrent() else { throw CancellationError() }
        requests.append(request)
        return self
    }
    func commit() async -> DeliveryReceipt {
        let result = DeliveryReceipt(operationID: requests.last!.id, disposition: .accepted,
            effect: .clipboard, confirmation: .clipboardValue)
        receipt = result
        return result
    }
    func close() async {}
}
