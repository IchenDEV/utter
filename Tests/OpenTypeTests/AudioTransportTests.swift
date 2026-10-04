import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
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
