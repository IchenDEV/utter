import Foundation
import XCTest
import UtterContracts
import UtterPresentationContracts

@MainActor
final class UpdatePresentationTests: XCTestCase {
    private func withLanguage(_ language: UILanguage, _ body: () -> Void) {
        Loc.use(language)
        defer { Loc.use(.chinese) }
        body()
    }

    func testMenuTitleNamesTheVersionOnlyWhenAnUpdateIsAvailable() {
        withLanguage(.english) {
            XCTAssertEqual(UpdatePresentation.menuTitle(.available(version: "1.2.3")), "Update Available — v1.2.3")
            XCTAssertEqual(UpdatePresentation.menuTitle(.idle), "Check for Updates…")
            XCTAssertEqual(UpdatePresentation.menuTitle(.upToDate), "Check for Updates…")
            XCTAssertEqual(UpdatePresentation.menuTitle(.failed("x")), "Check for Updates…")
            XCTAssertEqual(UpdatePresentation.menuTitle(.checking), "Checking for updates…")
        }
        withLanguage(.chinese) {
            XCTAssertEqual(UpdatePresentation.menuTitle(.available(version: "1.2.3")), "有可用更新 — v1.2.3")
            XCTAssertEqual(UpdatePresentation.menuTitle(.idle), "检查更新…")
        }
    }

    func testStatusLineCoversEveryReportableState() {
        withLanguage(.english) {
            XCTAssertNil(UpdatePresentation.statusLine(.idle))
            XCTAssertNil(UpdatePresentation.statusLine(.unavailable(.missingFeed)))
            XCTAssertEqual(UpdatePresentation.statusLine(.checking), "Checking for updates…")
            XCTAssertEqual(UpdatePresentation.statusLine(.upToDate), "Utter is up to date.")
            XCTAssertEqual(UpdatePresentation.statusLine(.available(version: "2.0")), "Version 2.0 is available.")
            XCTAssertEqual(
                UpdatePresentation.statusLine(.pendingRestart(version: "2.0")), "Version 2.0 will install when Utter is idle.")
            XCTAssertEqual(UpdatePresentation.statusLine(.failed("raw sparkle text")), "The update check failed. Try again later.")
        }
    }

    func testFailureNeverShowsTheRawUpdaterMessage() {
        let line = UpdatePresentation.statusLine(.failed("SECRET-RAW-DETAIL")) ?? ""
        XCTAssertFalse(line.contains("SECRET-RAW-DETAIL"))
    }

    func testCheckingIsOnlyAllowedWhenNothingIsInFlight() {
        XCTAssertTrue(UpdatePresentation.canCheck(.idle))
        XCTAssertTrue(UpdatePresentation.canCheck(.upToDate))
        XCTAssertTrue(UpdatePresentation.canCheck(.available(version: "2.0")))
        XCTAssertTrue(UpdatePresentation.canCheck(.failed("x")))
        XCTAssertFalse(UpdatePresentation.canCheck(.checking))
        XCTAssertFalse(UpdatePresentation.canCheck(.pendingRestart(version: "2.0")))
        XCTAssertFalse(UpdatePresentation.canCheck(.unavailable(.adHocSigned)))
    }

    func testOnlyActionableStatesAreHighlighted() {
        XCTAssertTrue(UpdatePresentation.isHighlighted(.available(version: "2.0")))
        XCTAssertTrue(UpdatePresentation.isHighlighted(.pendingRestart(version: "2.0")))
        XCTAssertFalse(UpdatePresentation.isHighlighted(.idle))
        XCTAssertFalse(UpdatePresentation.isHighlighted(.failed("x")))
    }

    func testProjectionFollowsServiceAndStopsAfterDispose() {
        let service = FakeUpdateService()
        let projection = UpdateProjection(service: service)
        XCTAssertEqual(projection.status, .idle)
        service.publish(.available(version: "2.0"))
        XCTAssertEqual(projection.status, .available(version: "2.0"))
        projection.checkForUpdates()
        XCTAssertEqual(service.checks, 1)
        projection.dispose()
        service.publish(.upToDate)
        XCTAssertEqual(projection.status, .available(version: "2.0"))
        XCTAssertTrue(service.observers.isEmpty)
    }
}

@MainActor
private final class FakeUpdateService: UpdateService {
    var status: UpdateStatus = .idle
    var observers: [UUID: @MainActor (UpdateStatus) -> Void] = [:]
    var checks = 0
    func publish(_ next: UpdateStatus) {
        status = next
        for observer in Array(observers.values) { observer(next) }
    }
    func observe(_ callback: @escaping @MainActor (UpdateStatus) -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }
    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    func checkForUpdates() { checks += 1 }
}
