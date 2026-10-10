import XCTest
@testable import UtterAudio

final class AudioTailDrainTests: XCTestCase {
    func testDrainIncludesOneObservedTapQuantumAndRemainsBounded() {
        XCTAssertEqual(AudioTailDrain.duration(frameCount: 4096, sampleRate: 48_000), .seconds(4096.0 / 48_000 + 0.02))
        XCTAssertEqual(AudioTailDrain.duration(frameCount: 4096, sampleRate: 16_000), .seconds(4096.0 / 16_000 + 0.02))
        XCTAssertEqual(AudioTailDrain.duration(frameCount: Int.max, sampleRate: 16_000), .milliseconds(300))
        XCTAssertEqual(AudioTailDrain.duration(frameCount: 1, sampleRate: 48_000), .milliseconds(40))
    }

    func testInvalidOrUnavailableFormatAddsNoCaptureTime() {
        for rate in [Double.nan, .infinity, 0, -1] {
            XCTAssertEqual(AudioTailDrain.duration(frameCount: 4096, sampleRate: rate), .zero)
        }
        XCTAssertEqual(AudioTailDrain.duration(frameCount: 0, sampleRate: 48_000), .zero)
    }
}
