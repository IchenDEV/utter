import XCTest
import UtterContracts
@testable import UtterRemoteMic

@MainActor
final class RemoteButtonMappingCoordinatorTests: XCTestCase {
    private let f5 = RemoteKeyMappingPolicy.ours
    private let right = KeyMappingEntry(source: RemoteButton.right.hidSource, destination: 0)
    private let home = KeyMappingEntry(source: RemoteButton.home.hidSource, destination: 0)

    private func rig() -> CoordinatorRig {
        let rig = CoordinatorRig()
        addTeardownBlock { @MainActor in rig.stop() }
        return rig
    }

    private var rightBound: RemoteButtonProfile { .binding([(.right, .single, .showDesktop)]) }

    // MARK: off means untouched

    func testOffMakesNoWritesOpensNothingAndRequestsNothing() {
        let rig = rig()
        rig.coordinator.setProfile(rightBound)
        rig.coordinator.refresh()
        rig.coordinator.requestPermission()
        XCTAssertTrue(rig.source.refreshes.isEmpty)
        XCTAssertEqual(rig.source.stops, 0)
        XCTAssertTrue(rig.service.writes.isEmpty)
        XCTAssertEqual(rig.coordinator.state, .off)
    }

    func testEnablingChecksWithoutPromptingUnlessTheUserJustTurnedItOn() {
        let first = rig()
        first.start()
        XCTAssertEqual(first.source.refreshes, [false])
        let second = rig()
        second.start(prompt: true)
        XCTAssertEqual(second.source.refreshes, [true])
    }

    // MARK: silence only while observed

    func testPermissionNeededWritesNothingBeyondTheVoiceKey() {
        let rig = rig()
        rig.source.status = .needsPermission(canAsk: false)
        rig.start(profile: rightBound)
        XCTAssertEqual(rig.service.entries, [f5])
        XCTAssertFalse(rig.service.writes.contains { $0.contains(right) })
        XCTAssertEqual(rig.coordinator.state, .needsPermission(canAsk: false))
    }

    func testNothingBeyondTheVoiceKeyIsWrittenWhileTheRemoteIsNotSeen() {
        let rig = rig()
        rig.source.status = .waitingForRemote
        rig.start(profile: rightBound)
        XCTAssertEqual(rig.service.entries, [f5])
        XCTAssertEqual(rig.coordinator.state, .waitingForRemote)
        rig.source.status = .live
        rig.source.onDevicesChanged?()
        XCTAssertEqual(rig.service.entries, [f5, right])
        XCTAssertEqual(rig.coordinator.state, .active)
    }

    func testNeedsRestartIsReportedAndWritesNothingBeyondTheVoiceKey() {
        let rig = rig()
        rig.source.status = .needsRestart
        rig.start(profile: rightBound)
        XCTAssertEqual(rig.service.entries, [f5])
        XCTAssertEqual(rig.coordinator.state, .needsRestart)
    }

    func testAFailedSourceNeverSilencesAnything() {
        let rig = rig()
        rig.source.status = .failed
        rig.start(profile: rightBound)
        XCTAssertEqual(rig.service.entries, [f5])
        XCTAssertEqual(rig.coordinator.state, .failed)
    }

    func testGrantingPermissionLaterAppliesOnTheNextRefresh() {
        let rig = rig()
        rig.source.status = .needsPermission(canAsk: true)
        rig.start(profile: rightBound)
        XCTAssertEqual(rig.coordinator.state, .needsPermission(canAsk: true))
        rig.source.status = .live
        rig.coordinator.refresh()
        XCTAssertEqual(rig.service.entries, [f5, right])
        XCTAssertEqual(rig.coordinator.state, .active)
    }

    func testAskingFromThePageSendsThePromptAndFollowsTheAnswer() {
        let rig = rig()
        rig.source.status = .needsPermission(canAsk: true)
        rig.source.statusAfterPrompt = .needsPermission(canAsk: false)
        rig.start(profile: rightBound)
        rig.coordinator.requestPermission()
        XCTAssertEqual(rig.source.refreshes, [false, true])
        XCTAssertEqual(rig.coordinator.state, .needsPermission(canAsk: false))
        XCTAssertEqual(rig.service.entries, [f5])
    }

    // MARK: losing and regaining the source

    func testLosingPermissionRemovesOwnedEntriesAtOnceAndKeepsTheVoiceKey() {
        let rig = rig()
        rig.start(profile: .binding([(.right, .single, .showDesktop), (.home, .single, .appSwitcher)]))
        XCTAssertEqual(rig.service.entries, [f5, right, home])
        rig.source.status = .needsPermission(canAsk: false)
        rig.coordinator.refresh()
        XCTAssertEqual(rig.service.entries, [f5])
        XCTAssertEqual(rig.coordinator.state, .needsPermission(canAsk: false))
    }

    func testRemoteDisconnectAndReconnectReappliesOnTheNewService() {
        let rig = rig()
        rig.start(profile: rightBound)
        rig.provider.services = []
        rig.source.status = .waitingForRemote
        rig.source.onDevicesChanged?()
        XCTAssertEqual(rig.coordinator.state, .waitingForRemote)
        let reconnected = FakeKeyService(id: 2)
        rig.provider.services = [reconnected]
        rig.source.status = .live
        rig.source.onDevicesChanged?()
        XCTAssertEqual(reconnected.entries, [f5, right])
        XCTAssertEqual(rig.coordinator.state, .active)
    }

    func testDisablingRemovesTheSilenceBeforeTheObserverIsStopped() {
        let rig = rig()
        rig.start(profile: rightBound)
        var entriesWhenStopped: [KeyMappingEntry]?
        rig.source.onStop = { [service = rig.service] in entriesWhenStopped = service.entries }
        rig.coordinator.setEnabled(false)
        XCTAssertEqual(entriesWhenStopped, [f5], "no owned key may stay silenced once nothing observes it")
        XCTAssertEqual(rig.source.stops, 1)
        XCTAssertEqual(rig.coordinator.state, .off)
    }

    func testDisablingWhileThePermissionWasNeverGrantedTouchesNothingElse() {
        let rig = rig()
        rig.source.status = .needsPermission(canAsk: true)
        rig.start(profile: rightBound)
        rig.coordinator.setEnabled(false)
        XCTAssertEqual(rig.service.entries, [f5])
        XCTAssertFalse(rig.service.writes.contains { $0.contains(right) })
    }

    // MARK: editing the profile

    func testEditingWhileLiveRetargetsWithoutAConflict() {
        let rig = rig()
        rig.start(profile: rightBound)
        rig.coordinator.setProfile(.binding([(.right, .single, .showDesktop), (.home, .long, .appSwitcher)]))
        XCTAssertEqual(rig.service.entries, [f5, right, home])
        XCTAssertEqual(rig.controller.reapplyCount, 0)
        XCTAssertEqual(rig.coordinator.state, .active)
        rig.coordinator.setProfile(RemoteButtonProfile())
        XCTAssertEqual(rig.service.entries, [f5])
        XCTAssertEqual(rig.coordinator.state, .active)
    }

    func testEditingWhileNotLiveStoresTheProfileButWritesNothing() {
        let rig = rig()
        rig.source.status = .needsPermission(canAsk: false)
        rig.start()
        rig.coordinator.setProfile(rightBound)
        XCTAssertEqual(rig.service.entries, [f5])
        rig.source.status = .live
        rig.coordinator.refresh()
        XCTAssertEqual(rig.service.entries, [f5, right])
    }

    func testStateChangesAreReportedOnceEach() {
        let rig = rig()
        rig.start(profile: rightBound)
        rig.coordinator.refresh()
        rig.coordinator.refresh()
        rig.source.status = .needsPermission(canAsk: false)
        rig.coordinator.refresh()
        rig.coordinator.refresh()
        XCTAssertEqual(rig.states, [.active, .needsPermission(canAsk: false)])
    }
}
