import Foundation
import XCTest
import UtterContracts
@testable import UtterUpdates

@MainActor
private final class FakeDriver: UpdateDriver {
    struct StartFailure: Error {}
    var failOnStart = false
    var startedWith: [Bool] = []
    var automaticChecks: [Bool] = []
    var checks = 0
    var stops = 0
    func start(automaticChecks: Bool) throws {
        if failOnStart { throw StartFailure() }
        startedWith.append(automaticChecks)
    }
    func setAutomaticChecks(_ enabled: Bool) { automaticChecks.append(enabled) }
    func checkForUpdates() { checks += 1 }
    func stop() { stops += 1 }
}

@MainActor
final class UpdateControllerTests: XCTestCase {
    private let key = Data(repeating: 3, count: 32).base64EncodedString()
    private var enabled: UpdateConfiguration.Resolution {
        .enabled(UpdateConfiguration(feedURL: URL(string: "https://example.com/appcast.xml")!, publicKey: key))
    }

    private func makeController(_ resolution: UpdateConfiguration.Resolution? = nil, driver: FakeDriver? = nil)
        -> (UpdateController, FakeDriver, hooks: () -> UpdateDriverHooks?) {
        let driver = driver ?? FakeDriver()
        var captured: UpdateDriverHooks?
        let controller = UpdateController(resolution: resolution ?? enabled) { _, hooks in
            captured = hooks
            return driver
        }
        return (controller, driver, { captured })
    }

    func testUnavailableConfigurationNeverCreatesADriver() {
        var created = 0
        let controller = UpdateController(resolution: .unavailable(.missingFeed)) { _, _ in
            created += 1
            return FakeDriver()
        }
        controller.start(automaticChecks: true)
        controller.checkForUpdates()
        XCTAssertEqual(created, 0)
        XCTAssertEqual(controller.status, .unavailable(.missingFeed))
    }

    func testStartPassesTheAutomaticCheckPreferenceAndStaysIdle() {
        let (controller, driver, _) = makeController()
        controller.start(automaticChecks: false)
        XCTAssertEqual(driver.startedWith, [false])
        XCTAssertEqual(controller.status, .idle)
        controller.start(automaticChecks: true)
        XCTAssertEqual(driver.startedWith, [false], "starting twice must not restart the updater")
    }

    func testPreferenceChangesReachTheRunningDriver() {
        let (controller, driver, _) = makeController()
        controller.setAutomaticChecks(false)
        XCTAssertTrue(driver.automaticChecks.isEmpty, "nothing to configure before start")
        controller.start(automaticChecks: true)
        controller.setAutomaticChecks(false)
        XCTAssertEqual(driver.automaticChecks, [false])
    }

    func testManualCheckReportsCheckingThenTheDriverOutcome() {
        let (controller, driver, hooks) = makeController()
        var seen: [UpdateStatus] = []
        _ = controller.observe { seen.append($0) }
        controller.start(automaticChecks: true)
        controller.checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
        hooks()?.emit(.foundUpdate(version: "2.0"))
        hooks()?.emit(.cycleFinished)
        XCTAssertEqual(seen, [.checking, .available(version: "2.0")])
        XCTAssertEqual(controller.status, .available(version: "2.0"))
    }

    func testFailuresAreLoggedForDiagnostics() {
        var logged: [String] = []
        var captured: UpdateDriverHooks?
        let controller = UpdateController(resolution: enabled, log: { logged.append($0) }) { _, hooks in
            captured = hooks
            return FakeDriver()
        }
        controller.start(automaticChecks: true)
        captured?.emit(.failed("feed unreachable"))
        XCTAssertEqual(logged, ["Update check failed: feed unreachable"])
        XCTAssertEqual(controller.status, .failed("feed unreachable"))
    }

    func testRemovedObserverStopsReceivingStatus() {
        let (controller, _, _) = makeController()
        var count = 0
        let id = controller.observe { _ in count += 1 }
        controller.start(automaticChecks: true)
        controller.checkForUpdates()
        controller.removeObserver(id)
        controller.checkForUpdates()
        XCTAssertEqual(count, 1)
    }

    func testStartFailureTurnsTheUpdaterOffWithoutLeavingADriver() {
        let driver = FakeDriver()
        driver.failOnStart = true
        let (controller, _, _) = makeController(driver: driver)
        controller.start(automaticChecks: true)
        XCTAssertEqual(controller.status, .unavailable(.startFailed))
        XCTAssertEqual(driver.stops, 1)
        controller.checkForUpdates()
        XCTAssertEqual(driver.checks, 0)
    }

    func testRelaunchProceedsAtOnceWhenIdle() {
        let (controller, _, hooks) = makeController()
        controller.start(automaticChecks: true)
        let held = hooks()?.postponeRelaunch("2.0") {}
        XCTAssertEqual(held, false)
        XCTAssertEqual(controller.status, .idle)
    }

    func testRelaunchIsHeldWhileDictatingAndReleasedWhenTheSessionEnds() {
        let (controller, _, hooks) = makeController()
        controller.start(automaticChecks: true)
        controller.setSessionBusy(true)
        var relaunches = 0
        XCTAssertEqual(hooks()?.postponeRelaunch("2.0") { relaunches += 1 }, true)
        XCTAssertEqual(controller.status, .pendingRestart(version: "2.0"))
        XCTAssertEqual(relaunches, 0)
        controller.setSessionBusy(false)
        XCTAssertEqual(relaunches, 1)
    }

    func testRelaunchIsHeldWhileModelWorkRuns() {
        let (controller, _, hooks) = makeController()
        controller.start(automaticChecks: true)
        controller.setModelBusy(true)
        var relaunches = 0
        XCTAssertEqual(hooks()?.postponeRelaunch("2.0") { relaunches += 1 }, true)
        controller.setModelBusy(false)
        XCTAssertEqual(relaunches, 1)
    }

    func testStopRevokesHeldRelaunchAndIgnoresLaterEvents() {
        let (controller, driver, hooks) = makeController()
        controller.start(automaticChecks: true)
        controller.setSessionBusy(true)
        var relaunches = 0
        _ = hooks()?.postponeRelaunch("2.0") { relaunches += 1 }
        let before = controller.status
        controller.stop()
        controller.setSessionBusy(false)
        hooks()?.emit(.failed("late"))
        controller.checkForUpdates()
        XCTAssertEqual(relaunches, 0)
        XCTAssertEqual(driver.stops, 1)
        XCTAssertEqual(driver.checks, 0)
        XCTAssertEqual(controller.status, before)
    }
}
