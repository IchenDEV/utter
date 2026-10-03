import Foundation
import UtterRuntime

package struct AudioFileMetadata: Equatable, Sendable {
    package let url: URL
    package let frameCount: Int64
    package let sampleRate: Double
    package let channels: UInt32
    package init(url: URL, frameCount: Int64, sampleRate: Double, channels: UInt32) {
        self.url = url
        self.frameCount = frameCount
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

package enum AudioFileError: Error, Equatable {
    case unreadable
    case invalidAudio
}

@MainActor
package protocol AudioFileService: AnyObject {
    func inspect(_ url: URL) throws -> AudioFileMetadata
}

@MainActor
package protocol SpeechEvidenceService: AnyObject {
    func containsSpeech(at url: URL?) async throws -> Bool
}

extension AudioServices {
    package static let files = ServiceKey<any AudioFileService>("audio.files")
    package static let evidence = ServiceKey<any SpeechEvidenceService>("audio.speech-evidence")
}
