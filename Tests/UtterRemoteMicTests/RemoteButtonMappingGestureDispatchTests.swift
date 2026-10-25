import XCTest
import UtterContracts
@testable import UtterRemoteMic

@MainActor
final class RemoteButtonMappingGestureDispatchTests: XCTestCase {
    private let f5 = RemoteKeyMappingPolicy.ours
    private let copy = ButtonAction.key(KeyChord(keyCode: 8, modifiers: [.command]))

    private func rig() -> CoordinatorRig {
        let rig = CoordinatorRig()
        addTeardownBlock { @MainActor in rig.stop() }
        return rig
    }

    private var rightBound: RemoteButtonProfile { .binding([(.right, .single, .showDesktop)]) }

    // MARK: gestures

    func testAPlainButtonFiresItsSingleActionAtPress() {
        let rig = rig()
        rig.start(profile: rightBound)
        rig.source.press(.right)
        XCTAssertEqual(rig.commands, [ButtonCommand(button: .right, trigger: .single, action: .showDesktop)])
        rig.source.release(.right)
        XCTAssertEqual(rig.commands.count, 1)
    }

    func testAButtonThatIsNotOwnedIsIgnoredEvenThoughItsPressesAreSeen() {
        let rig = rig()
        rig.start(profile: rightBound)
        rig.source.press(.home)
        rig.source.release(.home)
        XCTAssertTrue(rig.commands.isEmpty)
    }

    func testEmptyProfileDispatchesNothingAndOwnsNothing() {
        let rig = rig()
        rig.start()
        rig.source.press(.right)
        rig.source.release(.right)
        XCTAssertTrue(rig.commands.isEmpty)
        XCTAssertEqual(rig.service.entries, [f5])
    }

    func testSingleWaitsForTheDoubleClickWindowAndFiresFromTheWake() {
        let rig = rig()
        rig.start(profile: .binding([(.ok, .single, .showDesktop), (.ok, .double, copy)]))
        rig.source.press(.ok)
        rig.clock.advance(0.1)
        rig.source.release(.ok)
        XCTAssertTrue(rig.commands.isEmpty)
        XCTAssertEqual(rig.wakes.last.map { ($0.delay * 1000).rounded() }, 300)
        rig.fireWake()
        XCTAssertEqual(rig.commands, [ButtonCommand(button: .ok, trigger: .single, action: .showDesktop)])
    }

    func testDoubleFiresAtTheSecondPressAndNoSingleFollows() {
        let rig = rig()
        rig.start(profile: .binding([(.ok, .single, .showDesktop), (.ok, .double, copy)]))
        rig.source.press(.ok)
        rig.clock.advance(0.1)
        rig.source.release(.ok)
        rig.clock.advance(0.1)
        rig.source.press(.ok)
        XCTAssertEqual(rig.commands, [ButtonCommand(button: .ok, trigger: .double, action: copy)])
        rig.clock.advance(0.1)
        rig.source.release(.ok)
        rig.clock.advance(1)
        rig.wakes.last?.fire()
        XCTAssertEqual(rig.commands.count, 1)
    }

    func testLongFiresWhileStillHeldAndItsReleaseDoesNothing() {
        let rig = rig()
        rig.start(profile: .binding([(.menu, .long, .appSwitcher)]))
        rig.source.press(.menu)
        XCTAssertTrue(rig.commands.isEmpty)
        rig.fireWake()
        XCTAssertEqual(rig.commands, [ButtonCommand(button: .menu, trigger: .long, action: .appSwitcher)])
        rig.source.release(.menu)
        XCTAssertEqual(rig.commands.count, 1)
    }

    func testAShortPressOfALongOnlyButtonIsANativeSingle() {
        let rig = rig()
        rig.start(profile: .binding([(.menu, .long, .appSwitcher)]))
        rig.source.press(.menu)
        rig.clock.advance(0.1)
        rig.source.release(.menu)
        XCTAssertEqual(rig.commands, [ButtonCommand(button: .menu, trigger: .single, action: .native)])
    }

    func testNothingIsDispatchedWhileTheKeysAreNotYetSilenced() {
        let rig = rig()
        rig.provider.services = []
        rig.start(profile: rightBound)
        XCTAssertEqual(rig.coordinator.state, .waitingForRemote)
        rig.source.press(.right)
        rig.source.release(.right)
        XCTAssertTrue(rig.commands.isEmpty, "the native key would fire as well")
    }

    func testAnUnrelatedProfileEditKeepsAPendingDoubleClick() {
        let rig = rig()
        rig.start(profile: .binding([(.ok, .single, .showDesktop), (.ok, .double, copy)]))
        rig.source.press(.ok)
        rig.clock.advance(0.1)
        rig.source.release(.ok)
        rig.coordinator.setProfile(.binding([
            (.ok, .single, .showDesktop), (.ok, .double, copy), (.home, .single, .appSwitcher),
        ]))
        rig.clock.advance(0.1)
        rig.source.press(.ok)
        XCTAssertEqual(rig.commands, [ButtonCommand(button: .ok, trigger: .double, action: copy)])
    }

    func testChangingAButtonsGestureBindingsStartsItFresh() {
        let rig = rig()
        rig.start(profile: .binding([(.ok, .single, .showDesktop), (.ok, .double, copy)]))
        rig.source.press(.ok)
        rig.clock.advance(0.1)
        rig.source.release(.ok)
        rig.coordinator.setProfile(.binding([(.ok, .single, .showDesktop)]))
        rig.clock.advance(0.1)
        rig.source.press(.ok)
        XCTAssertEqual(rig.commands, [ButtonCommand(button: .ok, trigger: .single, action: .showDesktop)])
    }

    func testLosingTheSourceDropsAPendingGesture() {
        let rig = rig()
        rig.start(profile: .binding([(.ok, .single, .showDesktop), (.ok, .double, copy)]))
        rig.source.press(.ok)
        rig.clock.advance(0.1)
        rig.source.release(.ok)
        rig.source.status = .waitingForRemote
        rig.source.onDevicesChanged?()
        rig.source.status = .live
        rig.source.onDevicesChanged?()
        rig.clock.advance(0.1)
        rig.source.press(.ok)
        XCTAssertTrue(rig.commands.isEmpty, "a first press starts a new sequence, it is not a stale second press")
    }

    func testEdgesAfterDisablingAreIgnored() {
        let rig = rig()
        rig.start(profile: rightBound)
        rig.coordinator.setEnabled(false)
        rig.source.press(.right)
        XCTAssertTrue(rig.commands.isEmpty)
    }

    // MARK: raw HID values

    /// Raw values copied from the Batch 0 measurement (`evidence/batch0-keytable-raw.txt`): one
    /// press and release of right, then of OK. Every key also reports a rollover element
    /// (usage 1) and an array element (usage 0xFFFFFFFF), and neither may count as a press.
    func testReplayOfMeasuredRawValuesYieldsExactlyOnePressAndReleasePerKey() {
        let raw = """
        7 1 0
        7 79 1
        7 4294967295 5177344
        7 4294967295 0
        7 1 0
        7 79 0
        7 4294967295 0
        7 4294967295 40
        7 1 0
        7 40 1
        7 4294967295 2621440
        7 4294967295 0
        7 1 0
        7 40 0
        """
        let edges = raw.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: " ").compactMap { Int($0) }
            guard let edge = RemoteButtonEdge.decode(usagePage: parts[0], usage: parts[1], value: parts[2]) else { return nil }
            return "\(edge.button.rawValue) \(edge.isDown ? "down" : "up")"
        }
        XCTAssertEqual(edges, ["right down", "right up", "ok down", "ok up"])
    }

    func testOnlyNamedKeyboardElementsWithZeroOrOneAreEdges() {
        XCTAssertEqual(RemoteButtonEdge.decode(usagePage: 7, usage: 79, value: 1)?.button, .right)
        XCTAssertEqual(RemoteButtonEdge.decode(usagePage: 7, usage: 79, value: 1)?.isDown, true)
        XCTAssertEqual(RemoteButtonEdge.decode(usagePage: 7, usage: 79, value: 0)?.isDown, false)
        XCTAssertNil(RemoteButtonEdge.decode(usagePage: 7, usage: 4_294_967_295, value: 79), "array element")
        XCTAssertNil(RemoteButtonEdge.decode(usagePage: 7, usage: 4_294_967_295, value: 0))
        XCTAssertNil(RemoteButtonEdge.decode(usagePage: 7, usage: 79, value: 5_242_880))
        XCTAssertNil(RemoteButtonEdge.decode(usagePage: 7, usage: 79, value: 2))
        XCTAssertNil(RemoteButtonEdge.decode(usagePage: 12, usage: 79, value: 1))
        XCTAssertNil(RemoteButtonEdge.decode(usagePage: 7, usage: 62, value: 1), "the voice key is not a button")
        XCTAssertNil(RemoteButtonEdge.decode(usagePage: 7, usage: 1, value: 0))
    }
}
