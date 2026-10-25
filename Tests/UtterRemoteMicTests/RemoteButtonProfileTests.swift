import XCTest
@testable import UtterRemoteMic

final class RemoteButtonProfileTests: XCTestCase {
    private let copy = ButtonAction.key(KeyChord(keyCode: 8, modifiers: [.command]))

    // MARK: key table

    func testKeyTableMatchesTheMeasuredRemote() {
        XCTAssertEqual(RemoteButton.allCases.count, 11)
        XCTAssertEqual(RemoteButton.up.usage, 82)
        XCTAssertEqual(RemoteButton.back.usage, 241)
        XCTAssertEqual(RemoteButton.tv.usage, 53)
        XCTAssertEqual(RemoteButton.volumeDown.usage, 129)
        XCTAssertEqual(Set(RemoteButton.allCases.map(\.usage)).count, 11)
    }

    func testHIDSourceEncodesKeyboardPageInHighBits() {
        XCTAssertEqual(RemoteButton.right.hidSource, 0x7_0000_004F)
        XCTAssertEqual(RemoteButton.ok.hidSource, 30_064_771_112)
    }

    func testVoiceKeyIsNeverAButton() {
        XCTAssertNil(RemoteButton(usagePage: 7, usage: 62))
        XCTAssertFalse(RemoteButton.allCases.map(\.hidSource).contains(RemoteKeyMappingPolicy.voiceKeySource))
    }

    func testLookupByUsageNeedsTheKeyboardPage() {
        XCTAssertEqual(RemoteButton(usagePage: 7, usage: 79), .right)
        XCTAssertNil(RemoteButton(usagePage: 12, usage: 79))
        XCTAssertNil(RemoteButton(usagePage: 7, usage: 4_294_967_295))
    }

    func testNativeEventsFollowTheMeasurements() {
        XCTAssertEqual(RemoteButton.back.nativeEvent, NativeKeyEvent.none)
        XCTAssertEqual(RemoteButton.volumeUp.nativeEvent, .media(0))
        XCTAssertEqual(RemoteButton.volumeDown.nativeEvent, .media(1))
        XCTAssertEqual(RemoteButton.ok.nativeEvent, .key(code: 36, flags: 0))
        XCTAssertEqual(RemoteButton.home.nativeEvent, .key(code: 115, flags: 0x80_0000))
        XCTAssertEqual(RemoteButton.up.nativeEvent, .key(code: 126, flags: 0xA0_0000))
    }

    // MARK: ownership

    func testUntouchedProfileOwnsNothing() {
        let profile = RemoteButtonProfile()
        XCTAssertTrue(profile.ownedButtons.isEmpty)
        XCTAssertTrue(RemoteButton.allCases.allSatisfy { profile.bindings(for: $0).isNative })
    }

    func testAnyNonNativeTriggerOwnsTheButtonAndSettingBackReleasesIt() {
        var profile = RemoteButtonProfile()
        profile.set(copy, for: .long, of: .menu)
        XCTAssertTrue(profile.isOwned(.menu))
        XCTAssertEqual(profile.bindings(for: .menu).long, copy)
        XCTAssertEqual(profile.bindings(for: .menu).single, .native)
        profile.set(.native, for: .long, of: .menu)
        XCTAssertFalse(profile.isOwned(.menu))
        XCTAssertEqual(profile, RemoteButtonProfile())
    }

    func testOwnedButtonsFollowKeyTableOrderNotInsertionOrder() {
        var profile = RemoteButtonProfile()
        profile.set(.showDesktop, for: .single, of: .volumeDown)
        profile.set(.appSwitcher, for: .single, of: .up)
        profile.set(.showDesktop, for: .double, of: .home)
        XCTAssertEqual(profile.ownedButtons, [.up, .home, .volumeDown])
    }

    func testRestoreDefaultsClearsEverything() {
        var profile = RemoteButtonProfile()
        profile.set(copy, for: .single, of: .ok)
        profile.restoreDefaults()
        XCTAssertEqual(profile, RemoteButtonProfile())
    }

    // MARK: codec

    func testEveryActionKindRoundTrips() throws {
        let actions: [ButtonAction] = [
            copy, .system(.playPause), .showDesktop, .appSwitcher, .openApp(bundleID: "com.apple.Safari"),
            .key(KeyChord(keyCode: 53)),
        ]
        var profile = RemoteButtonProfile()
        for (index, action) in actions.enumerated() {
            profile.set(action, for: ButtonTrigger.allCases[index % 3], of: RemoteButton.allCases[index])
        }
        XCTAssertEqual(RemoteButtonProfile.decode(profile.encoded()), profile)
    }

    func testEncodingIsStableForTheSameProfile() {
        var profile = RemoteButtonProfile()
        profile.set(copy, for: .single, of: .ok)
        profile.set(.showDesktop, for: .long, of: .home)
        XCTAssertEqual(profile.encoded(), profile.encoded())
    }

    func testNothingStoredOrCorruptDataIsAnEmptyProfile() {
        XCTAssertEqual(RemoteButtonProfile.decode(nil), RemoteButtonProfile())
        XCTAssertEqual(RemoteButtonProfile.decode(Data("not json".utf8)), RemoteButtonProfile())
        XCTAssertEqual(RemoteButtonProfile.decode(Data("[1,2,3]".utf8)), RemoteButtonProfile())
        XCTAssertEqual(RemoteButtonProfile.decode(Data()), RemoteButtonProfile())
    }

    func testUnknownActionTypeBecomesNativeAndReleasesTheButton() {
        let json = #"{"version":1,"buttons":{"ok":{"single":{"type":"teleport"}}}}"#
        let profile = RemoteButtonProfile.decode(Data(json.utf8))
        XCTAssertFalse(profile.isOwned(.ok))
    }

    func testMalformedActionPayloadsBecomeNative() {
        for payload in [#"{"type":"key"}"#, #"{"type":"system","system":"warp"}"#, #"{"type":"openApp"}"#,
                        #"{"type":"openApp","bundleID":""}"#, #""just a string""#, "42"] {
            let json = #"{"version":1,"buttons":{"ok":{"single":\#(payload)}}}"#
            XCTAssertFalse(RemoteButtonProfile.decode(Data(json.utf8)).isOwned(.ok), payload)
        }
    }

    func testUnknownButtonIsIgnoredAndKnownOnesSurvive() {
        let json = #"{"version":9,"buttons":{"power":{"single":{"type":"showDesktop"}},"ok":{"long":{"type":"showDesktop"}}}}"#
        let profile = RemoteButtonProfile.decode(Data(json.utf8))
        XCTAssertEqual(profile.ownedButtons, [.ok])
        XCTAssertEqual(profile.bindings(for: .ok).long, .showDesktop)
    }

    func testShellStyleActionsDoNotExist() {
        let json = #"{"version":1,"buttons":{"ok":{"single":{"type":"shell","command":"rm -rf /"}}}}"#
        XCTAssertFalse(RemoteButtonProfile.decode(Data(json.utf8)).isOwned(.ok))
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
