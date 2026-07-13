import AVFoundation
import Foundation

final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let locale: Locale
    private let legacy: LegacyAppleSpeechEngine

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
        self.legacy = LegacyAppleSpeechEngine(locale: locale)
    }

    var isReady: Bool { legacy.isReady }
    var supportsStreaming: Bool { true }

    func requestAccess() {
        legacy.requestAccess()
    }

    func prepare() async {
        do {
            try await AppleSpeechAnalyzer.prepare(locale: locale)
        } catch {
            Log.info("[AppleSpeech] SpeechAnalyzer preparation deferred: \(error.localizedDescription)")
        }
    }

    func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        legacy.startListening(language: language, onPartialResult: onPartialResult)
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        legacy.appendAudioBuffer(buffer)
    }

    func finishListening(audioURL: URL?, language: String?) async throws -> String {
        let fallbackTask = Task {
            try await legacy.finishListening(audioURL: audioURL, language: language)
        }
        guard let audioURL else { return try await fallbackTask.value }

        do {
            let text = try await AppleSpeechAnalyzer.transcribe(
                audioURL: audioURL,
                locale: resolvedLocale(for: language)
            )
            legacy.cancelListening()
            let fallback = try? await fallbackTask.value
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallback ?? ""
                : text
        } catch {
            Log.info("[AppleSpeech] SpeechAnalyzer failed, using legacy result: \(error.localizedDescription)")
            return try await fallbackTask.value
        }
    }

    func cancelListening() {
        legacy.cancelListening()
    }

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard let audioURL else { throw AppleSpeechError.noAudioFile }
        do {
            let text = try await AppleSpeechAnalyzer.transcribe(
                audioURL: audioURL,
                locale: resolvedLocale(for: language)
            )
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        } catch {
            Log.info("[AppleSpeech] SpeechAnalyzer failed, using legacy recognizer: \(error.localizedDescription)")
        }
        return try await legacy.transcribe(audioURL: audioURL, language: language)
    }

    private func resolvedLocale(for language: String?) -> Locale {
        switch language {
        case "zh": return Locale(identifier: "zh-CN")
        case "en": return Locale(identifier: "en-US")
        case "ja": return Locale(identifier: "ja-JP")
        case "ko": return Locale(identifier: "ko-KR")
        case "yue": return Locale(identifier: "yue-CN")
        default: return locale
        }
    }
}
