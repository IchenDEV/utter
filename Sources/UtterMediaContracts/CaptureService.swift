import Foundation
import AVFoundation
import UtterContracts
import UtterRuntime

package enum CaptureSource: Equatable, Sendable {
    case local(deviceID: String?)
    case remote(token: UInt64)
}

package struct CaptureRequest: Sendable {
    package let source: CaptureSource
    package let thresholds: AudioActivityThresholds
    package init(source: CaptureSource, thresholds: AudioActivityThresholds = .default) {
        self.source = source
        self.thresholds = thresholds
    }
}

package struct CaptureCallbacks {
    package let level: (Float) -> Void
    package let buffer: ((AVAudioPCMBuffer) -> Void)?
    package let switchedInput: () -> Void
    package let inputUnavailable: () -> Void

    package init(
        level: @escaping (Float) -> Void = { _ in }, buffer: ((AVAudioPCMBuffer) -> Void)? = nil,
        switchedInput: @escaping () -> Void = {}, inputUnavailable: @escaping () -> Void = {}
    ) {
        self.level = level
        self.buffer = buffer
        self.switchedInput = switchedInput
        self.inputUnavailable = inputUnavailable
    }
}

package struct CapturedAudio: Sendable {
    package let url: URL?
    package let activity: AudioCaptureActivity
    package init(url: URL?, activity: AudioCaptureActivity) {
        self.url = url
        self.activity = activity
    }
}

@MainActor
package protocol OwnedRecording: AnyObject {
    func finish() async throws -> CapturedAudio
    func close() async
}

@MainActor
package protocol CaptureService: AnyObject {
    func begin(_ request: CaptureRequest, callbacks: CaptureCallbacks) async throws -> any OwnedRecording
}

package enum CaptureError: Error, Equatable {
    case busy
    case remoteUnavailable
    case startFailed(AudioCaptureStartFailure)
}

package enum AudioServices {
    package static let capture = ServiceKey<any CaptureService>("audio.capture")
}
