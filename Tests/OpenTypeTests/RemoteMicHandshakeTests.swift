import Foundation
import XCTest
@testable import OpenType

final class RemoteMicHandshakeTests: XCTestCase {
    func testCapabilitiesWaitForBothNotificationSubscriptions() {
        var handshake = RemoteMicHandshake()
        handshake.registerCharacteristic(.transmit)

        XCTAssertFalse(handshake.shouldRequestCapabilities, "no subscriptions yet")

        handshake.confirmSubscription(.audio)
        XCTAssertFalse(handshake.shouldRequestCapabilities, "control notification still missing")

        handshake.confirmSubscription(.control)
        XCTAssertTrue(handshake.shouldRequestCapabilities, "both subscriptions confirmed")
    }

    func testCapabilitiesWaitForTransmitCharacteristic() {
        var handshake = RemoteMicHandshake()
        handshake.confirmSubscription(.audio)
        handshake.confirmSubscription(.control)

        XCTAssertFalse(handshake.shouldRequestCapabilities, "transmit characteristic unknown")

        handshake.registerCharacteristic(.transmit)
        XCTAssertTrue(handshake.shouldRequestCapabilities)
    }

    func testCapabilitiesAreRequestedOnlyOncePerAttempt() {
        var handshake = RemoteMicHandshake()
        handshake.registerCharacteristic(.transmit)
        handshake.confirmSubscription(.audio)
        handshake.confirmSubscription(.control)

        XCTAssertTrue(handshake.shouldRequestCapabilities)
        handshake.markCapabilitiesRequested()
        XCTAssertFalse(handshake.shouldRequestCapabilities, "must not resend")
    }

    func testReadinessRequiresParsed16kHzCapabilities() {
        var handshake = RemoteMicHandshake()
        XCTAssertFalse(handshake.isReady)

        let eightKilohertz = RemoteMicCapabilities(
            version: 0x0100,
            codecs: 0x01,
            interaction: 0x03,
            frameSize: 120,
            selectedCodec: 0x01,
            sampleRate: 8_000
        )
        XCTAssertFalse(handshake.confirmCapabilities(eightKilohertz))
        XCTAssertFalse(handshake.isReady, "8 kHz must not become ready")

        let sixteenKilohertz = RemoteMicCapabilities.default
        XCTAssertTrue(handshake.confirmCapabilities(sixteenKilohertz))
        XCTAssertTrue(handshake.isReady)
    }

    func testResetClearsEveryGate() {
        var handshake = RemoteMicHandshake()
        handshake.registerCharacteristic(.transmit)
        handshake.confirmSubscription(.audio)
        handshake.confirmSubscription(.control)
        handshake.markCapabilitiesRequested()
        _ = handshake.confirmCapabilities(.default)
        XCTAssertTrue(handshake.isReady)

        handshake.reset()
        XCTAssertFalse(handshake.isReady)
        XCTAssertFalse(handshake.shouldRequestCapabilities)
        XCTAssertFalse(handshake.hasAllCharacteristics)
        XCTAssertFalse(handshake.subscriptionsReady)
    }

    /// A late subscription confirmation from a previous attempt must not let the
    /// next attempt skip its own gate; this models the reset between attempts.
    func testSubscriptionFromPreviousAttemptDoesNotLeakAfterReset() {
        var handshake = RemoteMicHandshake()
        handshake.registerCharacteristic(.transmit)
        handshake.confirmSubscription(.audio)

        handshake.reset()
        handshake.registerCharacteristic(.transmit)
        handshake.confirmSubscription(.control)

        XCTAssertFalse(handshake.shouldRequestCapabilities, "audio confirmation from before the reset must not count")
    }
}

/// The wanted-state invariant behind the fallback-leak fix: a failed start must
/// leave the bridge with nothing to adopt later.
final class RemoteMicWantedStateTests: XCTestCase {
    func testFailedStartLeavesNothingWanted() {
        var state = RemoteMicWantedState()
        // A start that wants, then fails before the stream begins.
        state.want()
        XCTAssertTrue(state.isActive)

        XCTAssertTrue(state.reset(), "the attempted session was live")
        XCTAssertFalse(state.isActive, "no residue may remain after a failed start")
    }

    func testReleaseReportsOnlyWhenThereWasAWant() {
        var state = RemoteMicWantedState()
        XCTAssertFalse(state.release(), "nothing to release before wanting")

        state.want()
        XCTAssertTrue(state.release())
        XCTAssertFalse(state.release(), "a second release must not report again")
    }

    func testResetReportsLiveSessionOnce() {
        var state = RemoteMicWantedState()
        state.want()
        state.beginStreaming()

        XCTAssertTrue(state.reset())
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.reset(), "already reset")
    }

    func testStreamingAloneStillCountsAsActive() {
        var state = RemoteMicWantedState()
        state.beginStreaming()
        XCTAssertTrue(state.isActive, "implicit audio start without an explicit want")
    }
}
