import XCTest
import UtterContracts
@testable import UtterRemoteMic

@MainActor
final class RemoteKeyMappingControllerTests: XCTestCase {
    private let ours = RemoteKeyMappingPolicy.ours
    private let capsToEscape = KeyMappingEntry(source: 0x7_0000_0039, destination: 0x7_0000_0029)
    private let foreignF5 = KeyMappingEntry(source: RemoteKeyMappingPolicy.voiceKeySource, destination: 0x7_0000_0041)

    private func make(_ services: [FakeKeyService] = []) -> (RemoteKeyMappingController, FakeKeyProvider, FakeClock) {
        let provider = FakeKeyProvider()
        provider.services = services
        let clock = FakeClock()
        let controller = RemoteKeyMappingController(provider: provider, now: { clock.time })
        return (controller, provider, clock)
    }

    func testStaysOffAndTouchesNothingUntilEnabled() {
        let service = FakeKeyService(id: 1)
        let (controller, provider, _) = make([service])
        controller.tick()
        controller.verifyNow()
        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(provider.queries, 0)
        XCTAssertTrue(service.writes.isEmpty)
    }

    func testEnablingWritesOurEntryAndReportsActiveOnlyAfterReadBack() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape])
        let (controller, _, _) = make([service])
        controller.setEnabled(true)
        XCTAssertEqual(service.entries, [capsToEscape, ours])
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
    }

    func testNoMatchingServiceMeansNoRemoteAndWritesNothing() {
        let (controller, _, _) = make()
        controller.setEnabled(true)
        XCTAssertEqual(controller.state, .noRemote)
        controller.setEnabled(false)
    }

    func testExpectingARemoteReportsWaitingUntilTheGraceEnds() {
        let (controller, _, clock) = make()
        controller.setEnabled(true)
        controller.expectRemote()
        XCTAssertEqual(controller.state, .waitingForService)
        clock.advance(31)
        controller.tick()
        XCTAssertEqual(controller.state, .noRemote)
        controller.setEnabled(false)
    }

    func testSetFailureRollsBackAndReportsWaitingThenActiveOnRetry() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape])
        service.failSets = 1
        let (controller, _, clock) = make([service])
        controller.setEnabled(true)
        XCTAssertEqual(service.entries, [capsToEscape])
        XCTAssertEqual(service.writes.last, [capsToEscape], "rolled back to the snapshot")
        XCTAssertEqual(controller.state, .waitingForService)
        clock.advance(1)
        controller.tick()
        XCTAssertEqual(service.entries, [capsToEscape, ours])
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
    }

    func testReadBackMismatchRollsBackAndEndsFailedAfterBoundedAttempts() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape])
        service.ignoreWrites = true
        let (controller, _, clock) = make([service])
        controller.setEnabled(true)
        for _ in 0..<40 {
            clock.advance(1)
            controller.tick()
        }
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(service.entries, [capsToEscape])
        let writesAtGiveUp = service.writes.count
        XCTAssertEqual(writesAtGiveUp, 20, "10 attempts, each a write plus a rollback write")
        clock.advance(100)
        controller.tick()
        XCTAssertEqual(service.writes.count, writesAtGiveUp, "no unbounded retry loop")
        controller.setEnabled(false)
    }

    func testUnreadableMappingIsNeverWrittenOver() {
        let service = FakeKeyService(id: 1, entries: nil)
        let (controller, _, clock) = make([service])
        controller.setEnabled(true)
        for _ in 0..<40 {
            clock.advance(1)
            controller.tick()
        }
        XCTAssertTrue(service.writes.isEmpty)
        XCTAssertEqual(controller.state, .failed)
        controller.setEnabled(false)
    }

    func testReappearingServiceAfterReconnectIsMappedAgain() {
        let first = FakeKeyService(id: 1)
        let (controller, provider, _) = make([first])
        controller.setEnabled(true)
        XCTAssertEqual(controller.state, .active)
        provider.services = []
        controller.tick()
        XCTAssertEqual(controller.state, .waitingForService)
        let second = FakeKeyService(id: 2)
        provider.services = [second]
        controller.tick()
        XCTAssertEqual(second.entries, [ours])
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
    }

    func testAForeignOverwriteIsReappliedOnceThenReportedAsConflict() {
        let service = FakeKeyService(id: 1)
        let (controller, _, _) = make([service])
        controller.setEnabled(true)
        service.entries = [foreignF5]
        controller.tick()
        XCTAssertEqual(service.entries, [ours])
        XCTAssertEqual(controller.reapplyCount, 1)
        service.entries = [foreignF5]
        controller.tick()
        XCTAssertEqual(controller.state, .conflict)
        let writes = service.writes.count
        controller.tick()
        controller.tick()
        XCTAssertEqual(service.writes.count, writes, "two tools never fight in a loop")
        XCTAssertEqual(service.entries, [foreignF5])
        controller.setEnabled(false)
        XCTAssertEqual(service.entries, [foreignF5], "restore leaves another tool's mapping alone")
    }

    func testDisablingRestoresTheForeignF5AndEverythingElse() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape, foreignF5])
        let (controller, _, _) = make([service])
        controller.setEnabled(true)
        XCTAssertEqual(service.entries, [capsToEscape, ours])
        controller.setEnabled(false)
        XCTAssertEqual(service.entries, [capsToEscape, foreignF5])
        XCTAssertEqual(controller.state, .off)
    }

    func testDisablingWhileRetryingWritesNothingMoreAndStopsRetrying() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape])
        service.failSets = 1
        let (controller, _, clock) = make([service])
        controller.setEnabled(true)
        let writes = service.writes.count
        controller.setEnabled(false)
        clock.advance(10)
        controller.tick()
        XCTAssertEqual(service.writes.count, writes)
        XCTAssertEqual(service.entries, [capsToEscape])
        XCTAssertEqual(controller.state, .off)
    }

    func testLeftoverOurEntryFromACrashIsAdoptedWithoutAWriteAndCleanedOnDisable() {
        let service = FakeKeyService(id: 1, entries: [ours])
        let (controller, _, _) = make([service])
        controller.setEnabled(true)
        XCTAssertTrue(service.writes.isEmpty)
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
        XCTAssertEqual(service.entries, [])
    }

    func testRepeatedCallsAreIdempotent() {
        let service = FakeKeyService(id: 1)
        let (controller, _, _) = make([service])
        controller.setEnabled(true)
        controller.setEnabled(true)
        for _ in 0..<5 { controller.verifyNow() }
        XCTAssertEqual(service.writes.count, 1)
        controller.setEnabled(false)
        controller.setEnabled(false)
        XCTAssertEqual(service.writes.count, 2)
    }

    func testOnlyServicesFromTheProviderAreEverWritten() {
        let remote = FakeKeyService(id: 1)
        let otherDevice = FakeKeyService(id: 99, entries: [capsToEscape])
        let (controller, _, _) = make([remote])
        controller.setEnabled(true)
        controller.setEnabled(false)
        XCTAssertTrue(otherDevice.writes.isEmpty)
        XCTAssertEqual(otherDevice.entries, [capsToEscape])
    }

    func testChangeCallbackFiresOnStateAndCounterChangesOnly() {
        let service = FakeKeyService(id: 1)
        let (controller, _, _) = make([service])
        var seen: [RemoteKeyRemapState] = []
        controller.onChange = { state, _ in seen.append(state) }
        controller.setEnabled(true)
        controller.tick()
        controller.tick()
        controller.setEnabled(false)
        XCTAssertEqual(seen, [.active, .off])
    }

    func testPollingLoopAppliesAServiceThatAppearsLater() async throws {
        let provider = FakeKeyProvider()
        let controller = RemoteKeyMappingController(
            provider: provider, timing: .init(pollInterval: 0.01)
        )
        controller.setEnabled(true)
        XCTAssertEqual(controller.state, .noRemote)
        let service = FakeKeyService(id: 7)
        provider.services = [service]
        for _ in 0..<200 where controller.state != .active { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
        XCTAssertEqual(service.entries, [])
    }
}
