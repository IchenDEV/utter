import XCTest
@testable import UtterAudio

final class CaptureFormatChoiceTests: XCTestCase {
    private func traits(_ rate: Double, _ channels: UInt32) -> CaptureFormatTraits {
        CaptureFormatTraits(sampleRate: rate, channelCount: channels)
    }

    /// The v0.0.59 failure: the engine kept the 48 kHz aggregate format while the
    /// built-in microphone ran at 44.1 kHz, so the tap received no frames.
    func testHardwareFormatWinsWhenEngineKeepsStaleAggregateRate() {
        XCTAssertEqual(
            CaptureFormatChoice.choose(hardware: traits(44_100, 1), client: traits(48_000, 1)),
            .hardware
        )
    }

    func testMatchingFormatsUseHardware() {
        XCTAssertEqual(
            CaptureFormatChoice.choose(hardware: traits(48_000, 2), client: traits(48_000, 2)),
            .hardware
        )
    }

    func testHardwareChannelCountIsHonored() {
        XCTAssertEqual(
            CaptureFormatChoice.choose(hardware: traits(48_000, 2), client: traits(48_000, 1)),
            .hardware
        )
    }

    func testUnconfiguredHardwareFallsBackToClient() {
        XCTAssertEqual(
            CaptureFormatChoice.choose(hardware: traits(0, 0), client: traits(48_000, 1)),
            .client
        )
        XCTAssertEqual(
            CaptureFormatChoice.choose(hardware: traits(44_100, 0), client: traits(48_000, 1)),
            .client
        )
        XCTAssertEqual(
            CaptureFormatChoice.choose(hardware: traits(.nan, 1), client: traits(48_000, 1)),
            .client
        )
    }

    func testNoUsableFormatIsReported() {
        XCTAssertEqual(
            CaptureFormatChoice.choose(hardware: traits(0, 0), client: traits(0, 0)),
            .unusable
        )
        XCTAssertEqual(
            CaptureFormatChoice.choose(hardware: traits(-1, 1), client: traits(.infinity, 1)),
            .unusable
        )
    }
}
