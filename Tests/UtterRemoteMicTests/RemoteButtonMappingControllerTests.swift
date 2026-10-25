import XCTest
import UtterContracts
@testable import UtterRemoteMic

@MainActor
final class RemoteButtonMappingControllerTests: XCTestCase {
    private let f5 = RemoteKeyMappingPolicy.ours
    private let right = KeyMappingEntry(source: RemoteButton.right.hidSource, destination: 0)
    private let home = KeyMappingEntry(source: RemoteButton.home.hidSource, destination: 0)
    private let foreignRight = KeyMappingEntry(source: RemoteButton.right.hidSource, destination: 0x7_0000_0041)
    private let capsToEscape = KeyMappingEntry(source: 0x7_0000_0039, destination: 0x7_0000_0029)

    private func make(_ service: FakeKeyService) -> (RemoteKeyMappingController, FakeKeyProvider, FakeClock) {
        let provider = FakeKeyProvider()
        provider.services = [service]
        let clock = FakeClock()
        let controller = RemoteKeyMappingController(provider: provider, now: { clock.time })
        return (controller, provider, clock)
    }

    private func sources(_ buttons: RemoteButton...) -> [UInt64] { buttons.map(\.hidSource) }

    // MARK: first application

    func testOwnedButtonsAreWrittenTogetherWithTheVoiceKeyInOneWrite() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape])
        let (controller, _, _) = make(service)
        controller.setOwnedSources(sources(.right, .home))
        controller.setEnabled(true)
        XCTAssertEqual(service.entries, [capsToEscape, f5, right, home])
        XCTAssertEqual(service.writes.count, 1)
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
    }

    func testChoosingButtonsWhileDisabledTouchesNothingUntilEnabled() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape])
        let (controller, provider, _) = make(service)
        controller.setOwnedSources(sources(.right))
        controller.tick()
        XCTAssertEqual(provider.queries, 0)
        XCTAssertTrue(service.writes.isEmpty)
        controller.setEnabled(true)
        XCTAssertEqual(service.entries, [capsToEscape, f5, right])
        controller.setEnabled(false)
    }

    func testUnknownSourcesAreNeverWritten() {
        let service = FakeKeyService(id: 1)
        let (controller, _, _) = make(service)
        controller.setOwnedSources([0x7_0000_0004, 0xC_0000_00E9])
        controller.setEnabled(true)
        XCTAssertEqual(service.entries, [f5])
        controller.setEnabled(false)
    }

    // MARK: editing while active

    func testEditingRetargetsWithoutCountingAReapplyOrReportingAConflict() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape])
        let (controller, _, _) = make(service)
        controller.setEnabled(true)
        controller.setOwnedSources(sources(.right))
        XCTAssertEqual(service.entries, [capsToEscape, f5, right])
        controller.setOwnedSources(sources(.right, .home))
        XCTAssertEqual(service.entries, [capsToEscape, f5, right, home])
        controller.tick()
        controller.tick()
        XCTAssertEqual(controller.reapplyCount, 0)
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
    }

    func testSettingTheSameSetAgainWritesNothing() {
        let service = FakeKeyService(id: 1)
        let (controller, _, _) = make(service)
        controller.setEnabled(true)
        controller.setOwnedSources(sources(.right))
        let writes = service.writes.count
        controller.setOwnedSources(sources(.right))
        controller.tick()
        XCTAssertEqual(service.writes.count, writes)
        controller.setEnabled(false)
    }

    func testReleasingAButtonRemovesItsEntryAndBringsBackAnotherToolsOne() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape, foreignRight])
        let (controller, _, _) = make(service)
        controller.setOwnedSources(sources(.right))
        controller.setEnabled(true)
        XCTAssertEqual(service.entries, [capsToEscape, f5, right])
        controller.setOwnedSources([])
        XCTAssertEqual(service.entries, [capsToEscape, foreignRight, f5])
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
        XCTAssertEqual(service.entries, [capsToEscape, foreignRight])
    }

    func testAnotherToolOverwritingAnOwnedButtonIsStillReappliedOnceThenConflict() {
        let service = FakeKeyService(id: 1)
        let (controller, _, _) = make(service)
        controller.setOwnedSources(sources(.right))
        controller.setEnabled(true)
        service.entries = [f5]
        controller.tick()
        XCTAssertEqual(controller.reapplyCount, 1)
        XCTAssertEqual(service.entries, [f5, right])
        service.entries = [f5]
        controller.tick()
        XCTAssertEqual(controller.state, .conflict)
        controller.setEnabled(false)
    }

    // MARK: disable and crash recovery

    func testDisablingRestoresAnotherToolsEntriesForEveryOwnedButton() {
        let service = FakeKeyService(id: 1, entries: [foreignRight, capsToEscape])
        let (controller, _, _) = make(service)
        controller.setOwnedSources(sources(.right, .home))
        controller.setEnabled(true)
        controller.setEnabled(false)
        XCTAssertEqual(service.entries, [capsToEscape, foreignRight])
        XCTAssertEqual(controller.state, .off)
    }

    func testLeftoverFromACrashWithAnotherProfileIsRepairedAndCleanedOnDisable() {
        let service = FakeKeyService(id: 1, entries: [f5, right, home])
        let (controller, _, _) = make(service)
        controller.setOwnedSources(sources(.right))
        controller.setEnabled(true)
        XCTAssertEqual(service.entries, [f5, right], "the home entry of the old profile is gone")
        controller.setEnabled(false)
        XCTAssertEqual(service.entries, [], "nothing of ours is resurrected")
    }

    func testLeftoverThatAlreadyMatchesIsAdoptedWithoutAWrite() {
        let service = FakeKeyService(id: 1, entries: [f5, right])
        let (controller, _, _) = make(service)
        controller.setOwnedSources(sources(.right))
        controller.setEnabled(true)
        XCTAssertTrue(service.writes.isEmpty)
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
    }

    // MARK: failures while editing

    func testRetargetWriteFailureRollsBackThenAppliesAndKeepsTheForeignOriginal() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape, foreignRight])
        let (controller, _, clock) = make(service)
        controller.setOwnedSources(sources(.right))
        controller.setEnabled(true)
        service.failSets = 1
        controller.setOwnedSources([])
        XCTAssertEqual(service.entries, [capsToEscape, f5, right], "rolled back to the state before the edit")
        XCTAssertEqual(controller.state, .waitingForService)
        XCTAssertEqual(controller.reapplyCount, 0)
        clock.advance(1)
        controller.tick()
        XCTAssertEqual(service.entries, [capsToEscape, foreignRight, f5])
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
    }

    func testReadBackThatStillHoldsAStaleEntryIsNotAccepted() {
        let service = FakeKeyService(id: 1)
        let (controller, _, _) = make(service)
        controller.setOwnedSources(sources(.right))
        controller.setEnabled(true)
        service.ignoreWrites = true
        controller.setOwnedSources([])
        XCTAssertNotEqual(controller.state, .active, "a released key left silenced must not read as success")
        controller.setEnabled(false)
    }

    func testGivingUpAfterARetargetFailureStillRestoresOnDisable() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape, foreignRight])
        let (controller, _, clock) = make(service)
        controller.setOwnedSources(sources(.right))
        controller.setEnabled(true)
        service.ignoreWrites = true
        controller.setOwnedSources([])
        for _ in 0..<40 {
            clock.advance(1)
            controller.tick()
        }
        XCTAssertEqual(controller.state, .failed)
        service.ignoreWrites = false
        controller.setEnabled(false)
        XCTAssertEqual(service.entries, [capsToEscape, foreignRight])
    }

    func testAnEditAfterGivingUpGetsAFreshAttempt() {
        let service = FakeKeyService(id: 1, entries: [capsToEscape])
        let (controller, _, clock) = make(service)
        controller.setOwnedSources(sources(.right))
        controller.setEnabled(true)
        service.ignoreWrites = true
        controller.setOwnedSources(sources(.right, .home))
        for _ in 0..<40 {
            clock.advance(1)
            controller.tick()
        }
        XCTAssertEqual(controller.state, .failed)
        service.ignoreWrites = false
        controller.setOwnedSources(sources(.home))
        XCTAssertEqual(service.entries, [capsToEscape, f5, home])
        XCTAssertEqual(controller.state, .active)
        controller.setEnabled(false)
        XCTAssertEqual(service.entries, [capsToEscape])
    }
}
