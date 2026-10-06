import Foundation
import XCTest
@testable import OpenType

@MainActor
final class RemoteMicHostSessionTests: XCTestCase {
    private let capabilities = Data([0x0B, 0x01, 0x00, 0x02, 0x03, 0x00, 0x78])
    private let audioStart = Data([0x04, 0x00, 0x02, 0x07])

    private func makeReadyBridge() throws -> (XiaomiRemoteMicBridge, XiaomiRemoteMicPeripheralDelegateProxy) {
        let bridge = XiaomiRemoteMicBridge()
        bridge.configureForTesting()
        _ = bridge.simulateConnectForTesting()
        bridge.markActiveForTesting()
        bridge.simulateCapabilitiesRequestedForTesting()
        let proxy = try XCTUnwrap(bridge.callbackProxyForTesting())
        proxy.deliverForTesting(.control(capabilities))
        return (bridge, proxy)
    }

    func testHostSessionLatchesOnceAndExposesItsToken() throws {
        let (bridge, _) = try makeReadyBridge()
        let token = try XCTUnwrap(bridge.beginHostSessionForTesting())

        XCTAssertEqual(bridge.currentSessionToken, token)
        XCTAssertNil(bridge.beginHostSessionForTesting(), "a live session must not be replaced")
    }

    func testRemoteStreamJoinsAHostSessionInsteadOfLatchingANewOne() throws {
        let (bridge, proxy) = try makeReadyBridge()
        let token = try XCTUnwrap(bridge.beginHostSessionForTesting())
        var pressed = false
        bridge.onVoiceKeyPressed = { _ in pressed = true }

        proxy.deliverForTesting(.control(audioStart))

        XCTAssertFalse(pressed, "the app already owns this recording")
        XCTAssertEqual(bridge.currentSessionToken, token)
    }

    func testStopFromThePreviousStreamDoesNotEndANewHostSession() throws {
        let (bridge, proxy) = try makeReadyBridge()
        _ = try XCTUnwrap(bridge.beginHostSessionForTesting())
        var released = false
        bridge.onVoiceKeyReleased = { released = true }

        proxy.deliverForTesting(.control(Data([0x00])))

        XCTAssertTrue(bridge.isSessionLive)
        XCTAssertFalse(released)
    }

    func testRemoteStopEndsAHostSessionOnceItsOwnStreamStarted() throws {
        let (bridge, proxy) = try makeReadyBridge()
        _ = try XCTUnwrap(bridge.beginHostSessionForTesting())
        var released = false
        bridge.onVoiceKeyReleased = { released = true }

        proxy.deliverForTesting(.control(audioStart))
        proxy.deliverForTesting(.control(Data([0x00])))

        XCTAssertFalse(bridge.isSessionLive)
        XCTAssertTrue(released, "a remote-side timeout must stop the recording")
    }

    func testVoiceKeyStillLatchesASessionWhenNoneIsLive() throws {
        let (bridge, proxy) = try makeReadyBridge()
        var pressedToken: UInt64?
        bridge.onVoiceKeyPressed = { pressedToken = $0 }

        proxy.deliverForTesting(.control(audioStart))

        XCTAssertNotNil(pressedToken)
        XCTAssertEqual(bridge.currentSessionToken, pressedToken)
    }

    func testMicrophoneExtendFollowsTheProtocolVersion() {
        XCTAssertEqual(RemoteMicProtocol.microphoneExtend(version: 0x0100, sessionID: 7), Data([0x0E, 0x07]))
        XCTAssertNil(RemoteMicProtocol.microphoneExtend(version: 0x0004, sessionID: 7))
    }
}
