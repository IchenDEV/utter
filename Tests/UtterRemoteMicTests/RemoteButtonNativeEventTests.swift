import XCTest
import UtterContracts
@testable import UtterRemoteMic

final class RemoteButtonNativeEventTests: XCTestCase {
    private let copy = ButtonAction.key(KeyChord(keyCode: 8, modifiers: [.command]))

    func testVoiceKeyIsNeverAButton() {
        XCTAssertNil(RemoteButton(usagePage: 7, usage: 62))
        XCTAssertFalse(RemoteButton.allCases.map(\.hidSource).contains(RemoteKeyMappingPolicy.voiceKeySource))
    }

    func testNativeEventsFollowTheMeasurements() {
        XCTAssertEqual(RemoteButton.back.nativeEvent, NativeKeyEvent.none)
        XCTAssertEqual(RemoteButton.volumeUp.nativeEvent, .media(0))
        XCTAssertEqual(RemoteButton.volumeDown.nativeEvent, .media(1))
        XCTAssertEqual(RemoteButton.ok.nativeEvent, .key(code: 36, flags: 0))
        XCTAssertEqual(RemoteButton.home.nativeEvent, .key(code: 115, flags: 0x80_0000))
        XCTAssertEqual(RemoteButton.up.nativeEvent, .key(code: 126, flags: 0xA0_0000))
    }

    // MARK: plan

    func testPlanListsOwnedButtonsWithSourcesAndGestureBindings() {
        var profile = RemoteButtonProfile()
        profile.set(copy, for: .single, of: .ok)
        profile.set(.showDesktop, for: .double, of: .home)
        profile.set(.appSwitcher, for: .long, of: .home)
        let plan = ButtonMappingPlan.make(from: profile)
        XCTAssertEqual(plan.owned.map(\.button), [.ok, .home])
        XCTAssertEqual(plan.sources, [RemoteButton.ok.hidSource, RemoteButton.home.hidSource])
        XCTAssertEqual(plan.owned[0].gestures, GestureBindings(hasDouble: false, hasLong: false))
        XCTAssertEqual(plan.owned[1].gestures, GestureBindings(hasDouble: true, hasLong: true))
    }

    func testEmptyProfileGivesAnEmptyPlanWithNoSources() {
        let plan = ButtonMappingPlan.make(from: RemoteButtonProfile())
        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.sources.isEmpty)
    }

    func testPlanNeverContainsTheVoiceKey() {
        var profile = RemoteButtonProfile()
        for button in RemoteButton.allCases { profile.set(.showDesktop, for: .single, of: button) }
        XCTAssertFalse(ButtonMappingPlan.make(from: profile).sources.contains(RemoteKeyMappingPolicy.voiceKeySource))
    }
}
