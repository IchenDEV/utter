import Foundation
import XCTest
import UtterContracts
import UtterRuntime
@testable import UtterModels

final class ModelResourceAccessTests: XCTestCase {
    func testNestedAccessOnTheSameGateDoesNotQueueBehindItself() async throws {
        let gate = LocalModelAccessGate()
        let result = try await gate.withAccess { try await gate.withAccess { 42 } }
        XCTAssertEqual(result, 42)
        let count = await gate.waitingTaskCount
        XCTAssertEqual(count, 0)
    }

    func testCancellationDrainsTheWaiterWithoutReleasingTheOwner() async throws {
        let gate = LocalModelAccessGate()
        try await gate.acquire()
        let waiter = Task { try await gate.withAccess { XCTFail("Cancelled waiter entered model work") } }
        for _ in 0..<500 {
            if await gate.waitingTaskCount == 1 { break }
            await Task.yield()
        }
        let queued = await gate.waitingTaskCount
        XCTAssertEqual(queued, 1)
        waiter.cancel()
        do { try await waiter.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        let remaining = await gate.waitingTaskCount
        XCTAssertEqual(remaining, 0)
        await gate.release()
        let next = try await gate.withAccess { "next" }
        XCTAssertEqual(next, "next")
    }

    func testThrowingModelWorkReleasesItsReservation() async throws {
        enum Failure: Error { case injected }
        let gate = LocalModelAccessGate()
        do { try await gate.withAccess { throw Failure.injected }; XCTFail("Expected failure") }
        catch Failure.injected {}
        let value = try await gate.withAccess { 7 }
        XCTAssertEqual(value, 7)
    }

    @MainActor
    func testThePluginProvidesTheProductionResourceContract() async throws {
        let runtime = PluginRuntime(catalog: try PluginCatalog([ModelPlugins.resourceAccess()]))
        try await runtime.start([PluginSelection("models.resource-access")])
        let service = try runtime.service(ModelServices.resourceAccess)
        let value = try await service.withAccess { 9 }
        XCTAssertEqual(value, 9)
        try await runtime.stop()
        do { _ = try await service.withAccess { 10 }; XCTFail("Disposed model service accepted work") }
        catch ModelResourceError.closed {}
    }

    @MainActor
    func testCloseRejectsWaitersAndWaitsForTheCurrentOwnerToDrain() async throws {
        let gate = LocalModelAccessGate()
        try await gate.acquire()
        let waiter = Task { try await gate.withAccess { XCTFail("Closed waiter ran") } }
        for _ in 0..<500 {
            if await gate.waitingTaskCount == 1 { break }
            await Task.yield()
        }
        var closed = false
        let shutdown = Task { await gate.close(); closed = true }
        for _ in 0..<500 {
            if await gate.isClosed { break }
            await Task.yield()
        }
        XCTAssertFalse(closed)
        do { try await waiter.value; XCTFail("Expected closed resource") }
        catch ModelResourceError.closed {}
        do { try await gate.acquire(); XCTFail("Expected closed resource") }
        catch ModelResourceError.closed {}
        await gate.release()
        await shutdown.value
        XCTAssertTrue(closed)
        await gate.close()
    }
}
