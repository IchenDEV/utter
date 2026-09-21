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
        handshake.registerCharacteristic(.transmit)
        handshake.confirmSubscription(.audio)
        handshake.confirmSubscription(.control)
        handshake.markCapabilitiesRequested()

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

    /// A capability frame that arrives before this attempt requested one (a late
    /// frame from a previous attempt on a reused peripheral) must not mark the
    /// new attempt ready.
    func testUnrequestedCapabilityResponseIsRejected() {
        var handshake = RemoteMicHandshake()
        handshake.registerCharacteristic(.transmit)
        handshake.confirmSubscription(.audio)
        handshake.confirmSubscription(.control)

        XCTAssertFalse(
            handshake.confirmCapabilities(.default),
            "a response before the request must be ignored"
        )
        XCTAssertFalse(handshake.isReady)

        handshake.markCapabilitiesRequested()
        XCTAssertTrue(handshake.confirmCapabilities(.default))
        XCTAssertTrue(handshake.isReady)
    }

    /// A late subscription confirmation from an old attempt must not let the
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

/// Attempt isolation on a reused `CBPeripheral`: CoreBluetooth queues callbacks
/// per object, so a callback raised during a previous connection can land after a
/// reconnect has already moved on. Peripheral identity alone cannot reject it;
/// the attempt stamped when the callback was raised can.
final class RemoteMicAttemptIsolationTests: XCTestCase {
    /// The reviewer's exact case: the new attempt has **already requested**
    /// capabilities when the old attempt's late capability response arrives.
    func testLateCapabilityFromPreviousAttemptIsRejectedAfterNewRequest() {
        var handshake = RemoteMicHandshake()
        handshake.beginAttempt(2)
        handshake.registerCharacteristic(.transmit)
        handshake.confirmSubscription(.audio)
        handshake.confirmSubscription(.control)
        handshake.markCapabilitiesRequested()

        // A capability that was raised during attempt 1 must be ignored even
        // though this handshake has now requested its own.
        XCTAssertFalse(handshake.accepts(1), "attempt 1 is stale")
        XCTAssertTrue(handshake.accepts(2))

        // The gate the bridge consults is the attempt check, so a stale frame
        // never reaches confirmCapabilities and cannot mark the attempt ready.
        XCTAssertFalse(handshake.isReady)
    }

    /// A late disconnect/control/audio from the previous attempt must be
    /// rejected by the same gate.
    func testLateControlAndAudioFromPreviousAttemptAreRejected() {
        var handshake = RemoteMicHandshake()
        handshake.beginAttempt(5)
        XCTAssertFalse(handshake.accepts(4), "stale control/audio attempt")
        XCTAssertTrue(handshake.accepts(5))
    }

    /// A new attempt starts from a clean gate even when the old one was ready.
    func testNewAttemptDoesNotInheritTheOldAttemptsState() {
        var handshake = RemoteMicHandshake()
        handshake.beginAttempt(1)
        handshake.registerCharacteristic(.transmit)
        handshake.confirmSubscription(.audio)
        handshake.confirmSubscription(.control)
        handshake.markCapabilitiesRequested()
        XCTAssertTrue(handshake.confirmCapabilities(.default))
        XCTAssertTrue(handshake.isReady)

        handshake.beginAttempt(2)
        XCTAssertFalse(handshake.isReady, "a new attempt must not start ready")
        XCTAssertFalse(handshake.hasAllCharacteristics)
        XCTAssertFalse(handshake.subscriptionsReady)
        XCTAssertFalse(handshake.shouldRequestCapabilities)
        XCTAssertFalse(handshake.accepts(1))
    }

    /// `reset` keeps the current attempt identity, so callbacks already in flight
    /// for this attempt are still accepted after a transient reset.
    func testResetKeepsTheCurrentAttemptIdentity() {
        var handshake = RemoteMicHandshake()
        handshake.beginAttempt(7)
        handshake.reset()
        XCTAssertTrue(handshake.accepts(7), "reset must not invalidate the live attempt")
        XCTAssertEqual(handshake.attempt, 7)
    }
}
