import UtterMediaContracts
import UtterContracts
import AVFoundation
import Foundation

package final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let log: Log
    private let locale: Locale
    private let legacy: LegacyAppleSpeechEngine
    private let recognitionContextLock = NSLock()
    private var recognitionContext = SpeechRecognitionContext.empty

    package init(locale: Locale = Locale(identifier: "zh-CN"), log: Log) {
        self.log = log
        self.locale = locale
        self.legacy = LegacyAppleSpeechEngine(locale: locale, log: log)
    }

    package var isReady: Bool { legacy.isReady }
    package var supportsStreaming: Bool { true }

    package func requestAccess() {
        legacy.requestAccess()
    }

    package func requestPermission() async throws {
        try await legacy.requestPermission()
    }

    package func configureRecognition(context: SpeechRecognitionContext) {
        recognitionContextLock.lock()
        recognitionContext = context
        recognitionContextLock.unlock()
        legacy.configureRecognition(context: context)
    }

    package func prepare() async {
        do {
            try await AppleSpeechAnalyzer.prepare(locale: locale)
        } catch {
            self.log.info("[AppleSpeech] SpeechAnalyzer preparation deferred: \(error.localizedDescription)")
        }
    }

    package func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        legacy.startListening(language: language, onPartialResult: onPartialResult)
    }

    package func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        legacy.appendAudioBuffer(buffer)
    }

    package func finishListening(audioURL: URL?, language: String?) async throws -> String {
        let fallbackTask = Task {
            try await legacy.finishListening(audioURL: audioURL, language: language)
        }
        guard let audioURL else { return try await fallbackTask.value }

        do {
            let context = recognitionContextSnapshot()
            let text = try await AppleSpeechAnalyzer.transcribe(
                audioURL: audioURL,
                locale: resolvedLocale(for: language),
                context: context, log: log
            )
            legacy.cancelListening()
            let fallback = try? await fallbackTask.value
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallback ?? ""
                : text
        } catch {
            self.log.info("[AppleSpeech] SpeechAnalyzer failed, using legacy result: \(error.localizedDescription)")
            return try await fallbackTask.value
        }
    }

    package func cancelListening() {
        legacy.cancelListening()
    }

    package func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard let audioURL else { throw AppleSpeechError.noAudioFile }
        let context = recognitionContextSnapshot()
        return try await AppleSpeechTranscriptionFallback.run(analyzer: {
            try await AppleSpeechAnalyzer.transcribe(
                audioURL: audioURL,
                locale: resolvedLocale(for: language),
                context: context, log: log
            )
        }, legacy: { try await legacy.transcribe(audioURL: audioURL, language: language) },
            reportFailure: { log.info("[AppleSpeech] SpeechAnalyzer failed, using legacy recognizer: \($0.localizedDescription)") })
    }

    private func recognitionContextSnapshot() -> SpeechRecognitionContext {
        recognitionContextLock.lock()
        defer { recognitionContextLock.unlock() }
        return recognitionContext
    }

    private func resolvedLocale(for language: String?) -> Locale {
        switch language {
        case "zh": return Locale(identifier: "zh-CN")
        case "en": return Locale(identifier: "en-US")
        case "ja": return Locale(identifier: "ja-JP")
        case "ko": return Locale(identifier: "ko-KR")
        case "yue": return Locale(identifier: "zh-HK")
        default: return Locale.current
        }
    }
}
