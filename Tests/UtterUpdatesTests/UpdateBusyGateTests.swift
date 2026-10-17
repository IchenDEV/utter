import XCTest
@testable import UtterUpdates

@MainActor
final class UpdateBusyGateTests: XCTestCase {
    func testIdleGateLetsRelaunchProceedImmediately() {
        let gate = UpdateBusyGate()
        var ran = 0
        XCTAssertFalse(gate.postpone { ran += 1 })
        XCTAssertEqual(ran, 0, "an unheld relaunch is the caller's to run, not the gate's")
    }

    func testRelaunchHeldWhileSessionIsBusyRunsOnceWhenItEnds() {
        let gate = UpdateBusyGate()
        var ran = 0
        gate.setSessionBusy(true)
        XCTAssertTrue(gate.postpone { ran += 1 })
        XCTAssertEqual(ran, 0)
        gate.setSessionBusy(false)
        XCTAssertEqual(ran, 1)
        gate.setSessionBusy(true)
        gate.setSessionBusy(false)
        XCTAssertEqual(ran, 1, "must not fire twice")
    }

    func testRelaunchWaitsForEverySignalToClear() {
        let gate = UpdateBusyGate()
        var ran = 0
        gate.setSessionBusy(true)
        gate.setModelBusy(true)
        XCTAssertTrue(gate.postpone { ran += 1 })
        gate.setSessionBusy(false)
        XCTAssertEqual(ran, 0, "model work is still running")
        gate.setModelBusy(false)
        XCTAssertEqual(ran, 1)
    }

    func testModelWorkAloneHoldsTheRelaunch() {
        let gate = UpdateBusyGate()
        var ran = 0
        gate.setModelBusy(true)
        XCTAssertTrue(gate.isBusy)
        XCTAssertTrue(gate.postpone { ran += 1 })
        gate.setModelBusy(false)
        XCTAssertEqual(ran, 1)
    }

    func testSecondRequestReplacesTheFirstSoOnlyOneRelaunchRuns() {
        let gate = UpdateBusyGate()
        var first = 0
        var second = 0
        gate.setSessionBusy(true)
        XCTAssertTrue(gate.postpone { first += 1 })
        XCTAssertTrue(gate.postpone { second += 1 })
        gate.setSessionBusy(false)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
    }

    func testRevokeDropsTheHeldRelaunchAndRefusesNewOnes() {
        let gate = UpdateBusyGate()
        var ran = 0
        gate.setSessionBusy(true)
        XCTAssertTrue(gate.postpone { ran += 1 })
        gate.revoke()
        gate.setSessionBusy(false)
        XCTAssertEqual(ran, 0)
        gate.setSessionBusy(true)
        XCTAssertFalse(gate.postpone { ran += 1 })
        gate.setSessionBusy(false)
        XCTAssertEqual(ran, 0)
    }
}
