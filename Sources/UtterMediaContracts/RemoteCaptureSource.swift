import Foundation
import AVFoundation
import UtterContracts
import UtterRuntime

package protocol RemoteCaptureSource: AnyObject {
    var currentSessionToken: UInt64? { get }
    var thresholds: AudioActivityThresholds { get set }
    var lastRecordingURL: URL? { get }
    var lastActivity: AudioCaptureActivity { get }
    func start(token: UInt64, levelUpdate: @escaping (Float) -> Void, bufferUpdate: ((AVAudioPCMBuffer) -> Void)?) -> Bool
    func stop()
    func cleanupLastRecording()
}

package enum RemoteMicServices {
    package static let capture = ServiceKey<any RemoteCaptureSource>("remote-mic.capture")
}
