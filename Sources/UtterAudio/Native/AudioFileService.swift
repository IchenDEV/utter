import Foundation
import AVFoundation
import UtterMediaContracts

@MainActor
final class BorrowedAudioFileService: AudioFileService {
    private let isCurrent: () -> Bool
    init(isCurrent: @escaping () -> Bool) { self.isCurrent = isCurrent }

    func inspect(_ url: URL) throws -> AudioFileMetadata {
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
            throw AudioFileError.unreadable
        }
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard file.length > 0, format.sampleRate > 0, format.channelCount > 0 else { throw AudioFileError.invalidAudio }
            return AudioFileMetadata(url: url, frameCount: file.length, sampleRate: format.sampleRate, channels: format.channelCount)
        } catch {
            throw AudioFileError.invalidAudio
        }
    }
}
