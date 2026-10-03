import CoreAudio
import XCTest
import UtterAudio

final class AudioTransportTests: XCTestCase {
    func testBuiltInClassificationUsesTransportType() {
        XCTAssertTrue(AudioInputDevices.isBuiltIn(transportType: kAudioDeviceTransportTypeBuiltIn))
        XCTAssertFalse(AudioInputDevices.isBuiltIn(transportType: kAudioDeviceTransportTypeUSB))
        XCTAssertFalse(AudioInputDevices.isBuiltIn(transportType: nil))
    }
}
