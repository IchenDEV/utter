import CoreAudio
import XCTest
@testable import OpenType

final class AudioInputResolverTests: XCTestCase {
    private let builtIn = AudioInputDevice(uid: "builtin", name: "MacBook Microphone", isBuiltIn: true)
    private let display = AudioInputDevice(uid: "display", name: "Studio Display Microphone", isBuiltIn: false)
    private let usb = AudioInputDevice(uid: "usb", name: "USB Microphone", isBuiltIn: false)
    private let iphone = AudioInputDevice(uid: "iphone", name: "iPhone Microphone", isBuiltIn: false)

    // MARK: - Clamshell parsing

    func testClamshellParseTreatsOnlyTrueAsClosed() {
        XCTAssertTrue(ClamshellState.isClosed(fromClamshellState: NSNumber(value: true)))
        XCTAssertFalse(ClamshellState.isClosed(fromClamshellState: NSNumber(value: false)))
        XCTAssertFalse(ClamshellState.isClosed(fromClamshellState: nil))
        XCTAssertFalse(ClamshellState.isClosed(fromClamshellState: "not-a-bool"))
    }

    // MARK: - Transport classification

    func testBuiltInClassificationUsesTransportType() {
        XCTAssertTrue(AudioInputDevices.isBuiltIn(transportType: kAudioDeviceTransportTypeBuiltIn))
        XCTAssertFalse(AudioInputDevices.isBuiltIn(transportType: kAudioDeviceTransportTypeUSB))
        XCTAssertFalse(AudioInputDevices.isBuiltIn(transportType: nil))
    }

    // MARK: - Start resolution

    func testLidOpenHonorsPreferredBuiltIn() {
        XCTAssertEqual(
            AudioInputResolver.resolve(
                devices: [builtIn, display],
                preferredUID: "builtin",
                systemDefaultUID: "builtin",
                lidClosed: false
            ),
            .use(uid: "builtin")
        )
    }

    func testLidClosedReplacesPreferredBuiltInWithExternal() {
        XCTAssertEqual(
            AudioInputResolver.resolve(
                devices: [builtIn, display],
                preferredUID: "builtin",
                systemDefaultUID: "builtin",
                lidClosed: true
            ),
            .use(uid: "display")
        )
    }

    func testLidClosedWithOnlyBuiltInIsUnavailable() {
        XCTAssertEqual(
            AudioInputResolver.resolve(
                devices: [builtIn],
                preferredUID: "builtin",
                systemDefaultUID: "builtin",
                lidClosed: true
            ),
            .unavailable
        )
    }

    func testPreferredExternalAlwaysWinsWhenUsable() {
        XCTAssertEqual(
            AudioInputResolver.resolve(
                devices: [builtIn, display, usb],
                preferredUID: "usb",
                systemDefaultUID: "builtin",
                lidClosed: true
            ),
            .use(uid: "usb")
        )
    }

    func testMissingPreferredFallsBackToSystemDefault() {
        XCTAssertEqual(
            AudioInputResolver.resolve(
                devices: [builtIn, display],
                preferredUID: "gone",
                systemDefaultUID: "display",
                lidClosed: false
            ),
            .use(uid: "display")
        )
    }

    func testContinuityIPhoneIsEligibleFallback() {
        XCTAssertEqual(
            AudioInputResolver.resolve(
                devices: [builtIn, iphone],
                preferredUID: "builtin",
                systemDefaultUID: "builtin",
                lidClosed: true
            ),
            .use(uid: "iphone")
        )
    }

    func testLidOpenWithNoDefaultStillUsesBuiltIn() {
        XCTAssertEqual(
            AudioInputResolver.resolve(
                devices: [builtIn],
                preferredUID: nil,
                systemDefaultUID: nil,
                lidClosed: false
            ),
            .use(uid: "builtin")
        )
    }

    func testNoDevicesIsUnavailable() {
        XCTAssertEqual(
            AudioInputResolver.resolve(
                devices: [],
                preferredUID: nil,
                systemDefaultUID: nil,
                lidClosed: false
            ),
            .unavailable
        )
    }

    // MARK: - Mid-session failover

    func testFailoverKeepsUsableActiveDevice() {
        XCTAssertEqual(
            MicFailoverDecision.decide(
                activeUID: "display",
                devices: [builtIn, display],
                preferredUID: "builtin",
                systemDefaultUID: "builtin",
                lidClosed: false
            ),
            .keep
        )
    }

    func testFailoverSwitchesWhenLidClosesOverBuiltIn() {
        XCTAssertEqual(
            MicFailoverDecision.decide(
                activeUID: "builtin",
                devices: [builtIn, display],
                preferredUID: "builtin",
                systemDefaultUID: "builtin",
                lidClosed: true
            ),
            .switchTo(uid: "display")
        )
    }

    func testFailoverFailsWhenActiveLostWithNoAlternative() {
        XCTAssertEqual(
            MicFailoverDecision.decide(
                activeUID: "builtin",
                devices: [builtIn],
                preferredUID: "builtin",
                systemDefaultUID: "builtin",
                lidClosed: true
            ),
            .fail
        )
    }

    func testFailoverSwitchesWhenActiveDeviceRemoved() {
        XCTAssertEqual(
            MicFailoverDecision.decide(
                activeUID: "removed",
                devices: [builtIn, display],
                preferredUID: "builtin",
                systemDefaultUID: "builtin",
                lidClosed: false
            ),
            .switchTo(uid: "builtin")
        )
    }
}
