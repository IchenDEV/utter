import Foundation
import XCTest
import UtterContracts
import UtterRuntime
@testable import UtterUpdates

@MainActor
final class UpdatePluginTests: XCTestCase {
    func testBundleWithoutUpdateKeysStaysInertThroughTheWholeLifecycle() async throws {
        let bare = UpdateEnvironment(isApplicationBundle: true, isAdHocSigned: false, feedURL: nil, publicKey: nil)
        let fixture = try UpdatePluginFixture(environment: bare)
        try await fixture.start()
        let service = try fixture.service()
        service.checkForUpdates()
        XCTAssertEqual(service.status, .unavailable(.missingFeed))
        XCTAssertEqual(fixture.driversCreated.value, 0, "no updater object may exist")
        try await fixture.runtime.stop()
    }

    func testDriverStartsOnlyWhenIngressIsReadyWithTheSavedPreference() async throws {
        let fixture = try UpdatePluginFixture(automaticChecks: false)
        try await fixture.start()
        XCTAssertEqual(fixture.driver.startedWith, [false])
        XCTAssertEqual(try fixture.service().status, .idle)
        try await fixture.runtime.stop()
    }

    func testPreferenceChangeReachesTheDriver() async throws {
        let fixture = try UpdatePluginFixture(automaticChecks: true)
        try await fixture.start()
        fixture.settings.update { $0.automaticUpdateChecks = false }
        fixture.settings.update { $0.automaticUpdateChecks = true }
        XCTAssertEqual(fixture.driver.automaticChecks, [false, true])
        try await fixture.runtime.stop()
    }

    func testRelaunchWaitsForDictationAndModelDownloadsToFinish() async throws {
        let fixture = try UpdatePluginFixture()
        try await fixture.start()
        fixture.execution.setBusy(true)
        fixture.catalog.setDownloading(true)
        var relaunches = 0
        XCTAssertEqual(fixture.driver.hooks?.postponeRelaunch("2.0") { relaunches += 1 }, true)
        XCTAssertEqual(try fixture.service().status, .pendingRestart(version: "2.0"))
        fixture.execution.setBusy(false)
        XCTAssertEqual(relaunches, 0, "the model download is still running")
        fixture.catalog.setDownloading(false)
        XCTAssertEqual(relaunches, 1)
        try await fixture.runtime.stop()
    }

    func testBusyStateBeforeStartIsNotMissed() async throws {
        let fixture = try UpdatePluginFixture()
        fixture.execution.setBusy(true)
        try await fixture.start()
        XCTAssertEqual(fixture.driver.hooks?.postponeRelaunch("2.0") {}, true)
        try await fixture.runtime.stop()
    }

    func testStopDropsHeldRelaunchAndRemovesEveryObserver() async throws {
        let fixture = try UpdatePluginFixture()
        try await fixture.start()
        fixture.execution.setBusy(true)
        var relaunches = 0
        _ = fixture.driver.hooks?.postponeRelaunch("2.0") { relaunches += 1 }
        try await fixture.runtime.stop()
        fixture.execution.setBusy(false)
        XCTAssertEqual(relaunches, 0)
        XCTAssertEqual(fixture.driver.stops, 1)
        XCTAssertEqual(fixture.execution.observerCount, 0)
        XCTAssertEqual(fixture.catalog.observerCount, 0)
        XCTAssertTrue(fixture.settings.observers.isEmpty)
    }
}
