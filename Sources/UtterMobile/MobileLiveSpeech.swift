#if os(iOS)
import Foundation
import AVFoundation
import UtterContracts
import UtterAppleSpeech

/// Feeds the capture tap into live recognition. The input format is only known once buffers arrive, so the
/// first buffer starts the recognizer and later buffers wait here until it is ready.
final class MobileLiveSpeech: @unchecked Sendable {
    private let locale: Locale
    private let context: SpeechRecognitionContext
    private let onDraft: @Sendable (String) -> Void
    private let lock = NSLock()
    private var queued: [AVAudioPCMBuffer] = []
    private var transcription: AppleLiveTranscription?
    private var starting = false
    private var failed = false
    private var closed = false

    init(locale: Locale, context: SpeechRecognitionContext, onDraft: @escaping @Sendable (String) -> Void) {
        self.locale = locale; self.context = context; self.onDraft = onDraft
    }

    /// Audio thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !closed, !failed else { return }
        if let transcription { transcription.append(buffer); return }
        guard let copy = Self.copy(buffer) else { failed = true; return }
        queued.append(copy)
        guard !starting else { return }
        starting = true
        let format = buffer.format
        Task { await start(format) }
    }

    private func start(_ format: AVAudioFormat) async {
        let started = try? await AppleLiveTranscription.start(locale: locale, source: format, context: context, onDraft: onDraft)
        lock.lock(); defer { lock.unlock() }
        guard let started, !closed else { failed = true; queued = []; started?.cancel(); return }
        queued.forEach(started.append)
        queued = []
        transcription = started
    }

    /// The final text, or nil when live recognition was unavailable or produced nothing; the caller then
    /// transcribes the recorded file.
    func finish() async -> String? {
        for _ in 0..<40 {
            lock.lock(); let settled = transcription != nil || failed || !starting; lock.unlock()
            if settled { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        lock.lock(); closed = true; let current = transcription; lock.unlock()
        guard let current, let text = try? await current.finish(), !text.isEmpty else { return nil }
        return text
    }

    func cancel() {
        lock.lock(); closed = true; let current = transcription; queued = []; lock.unlock()
        current?.cancel()
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData, let target = copy.floatChannelData else { return nil }
        copy.frameLength = buffer.frameLength
        for channel in 0..<Int(buffer.format.channelCount) {
            target[channel].update(from: source[channel], count: Int(buffer.frameLength))
        }
        return copy
    }
}
#endif
