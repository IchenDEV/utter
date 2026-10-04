import UtterMediaContracts
import UtterContracts
import Foundation
@preconcurrency import Speech
import AVFoundation

package final class LegacyAppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let log: Log
    private var recognizer: SFSpeechRecognizer
    package var isReady: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var bestSoFar = ""
    private var finishContinuation: CheckedContinuation<String, Error>?
    private var recognitionContext = SpeechRecognitionContext.empty
    private let stateQueue = DispatchQueue(label: "opentype.apple-speech")

    /// Maximum time (seconds) to wait for the recognition task to deliver a final result.
    /// `SFSpeechRecognizer` on-device buffer recognition enforces its own ~1 min limit,
    /// so waiting longer than that buys nothing.
    private static let timeoutSeconds: TimeInterval = 60

    package init(locale: Locale = Locale(identifier: "zh-CN"), log: Log) {
        self.log = log
        recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer()!

    }

    package var supportsStreaming: Bool { true }

    package func configureRecognition(context: SpeechRecognitionContext) {
        stateQueue.sync {
            recognitionContext = context
        }
    }

    package func requestAccess() {
        guard !isReady else { return }
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    package func requestPermission() async throws {
        try Task.checkCancellation()
        guard !isReady else { return }
        let allowed = try await PermissionRequest.wait { completion in
            SFSpeechRecognizer.requestAuthorization { completion($0 == .authorized) }
        }
        try Task.checkCancellation()
        guard allowed else { throw AppleSpeechError.notAuthorized }
    }

    package func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        configureRecognizer(language: language)
        let contextualStrings = stateQueue.sync { recognitionContext.phrases }

        stateQueue.sync {
            self.teardownLocked()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.requiresOnDeviceRecognition = true
            request.contextualStrings = contextualStrings
            if #available(macOS 16, *) {
                request.addsPunctuation = true
            }

            self.bestSoFar = ""
            self.recognitionRequest = request
            self.recognitionTask = self.recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                self.stateQueue.async {
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.bestSoFar = text
                        onPartialResult(text)
                        if result.isFinal {
                            self.resolveStreamingContinuationLocked(.success(text))
                        }
                    }

                    if let error {
                        if self.bestSoFar.isEmpty {
                            self.resolveStreamingContinuationLocked(.failure(error))
                        } else {
                            self.log.info("[AppleSpeech] task ended with error but has partial: \(error.localizedDescription)")
                            self.resolveStreamingContinuationLocked(.success(self.bestSoFar))
                        }
                    }
                }
            }
        }
    }

    package func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        stateQueue.async {
            self.recognitionRequest?.append(buffer)
        }
    }

    package func finishListening(audioURL: URL?, language: String?) async throws -> String {
        let hasLiveRequest = stateQueue.sync { self.recognitionRequest != nil }
        if !hasLiveRequest {
            return try await transcribe(audioURL: audioURL, language: language)
        }

        return try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                self.finishContinuation = continuation
                self.recognitionRequest?.endAudio()
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds) { [weak self] in
                guard let self else { return }
                self.stateQueue.async {
                    guard self.finishContinuation != nil else { return }
                    self.recognitionTask?.cancel()
                    let text = self.bestSoFar
                    self.resolveStreamingContinuationLocked(.success(text))
                    self.log.info("[AppleSpeech] timeout after \(Self.timeoutSeconds)s, returning partial (\(text.count) chars)")
                }
            }
        }
    }

    package func cancelListening() {
        stateQueue.sync {
            self.recognitionRequest?.endAudio()
            self.recognitionTask?.cancel()
            if self.finishContinuation != nil {
                self.resolveStreamingContinuationLocked(.success(self.bestSoFar))
            } else {
                self.recognitionTask = nil
                self.recognitionRequest = nil
            }
        }
    }

    package func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard let url = audioURL else {
            throw AppleSpeechError.noAudioFile
        }

        if !isReady {
            try await requestPermission()
        }

        configureRecognizer(language: language)
        let contextualStrings = stateQueue.sync { recognitionContext.phrases }

        let log = self.log
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.requiresOnDeviceRecognition = true
            request.contextualStrings = contextualStrings
            if #available(macOS 16, *) {
                request.addsPunctuation = true
            }

            var hasResumed = false
            var bestSoFar = ""

            let task = recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let result {
                    bestSoFar = result.bestTranscription.formattedString
                    if result.isFinal {
                        hasResumed = true
                        continuation.resume(returning: bestSoFar)
                    }
                }

                if let error, !hasResumed {
                    hasResumed = true
                    if bestSoFar.isEmpty {
                        continuation.resume(throwing: error)
                    } else {
                        log.info("[AppleSpeech] task ended with error but has partial: \(error.localizedDescription)")
                        continuation.resume(returning: bestSoFar)
                    }
                }
            }

            // Timeout: if recognition hangs, return whatever we have collected.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds) {
                guard !hasResumed else { return }
                hasResumed = true
                task.cancel()
                log.info("[AppleSpeech] timeout after \(Self.timeoutSeconds)s, returning partial (\(bestSoFar.count) chars)")
                continuation.resume(returning: bestSoFar)
            }
        }
    }

    private func configureRecognizer(language: String?) {
        let localeId: String
        switch language {
        case "zh": localeId = "zh-CN"
        case "ja": localeId = "ja-JP"
        case "ko": localeId = "ko-KR"
        case "yue": localeId = "zh-HK"
        case "en": localeId = "en-US"
        default: localeId = Locale.current.identifier
        }

        if let newRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)) {
            recognizer = newRecognizer
        }
    }

    /// Must be called on `stateQueue`.
    private func resolveStreamingContinuationLocked(_ result: Result<String, Error>) {
        let continuation = finishContinuation
        finishContinuation = nil
        recognitionTask = nil
        recognitionRequest = nil

        switch result {
        case .success(let text):
            continuation?.resume(returning: text)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    /// Must be called on `stateQueue`. Tears down any in-flight task without
    /// touching `finishContinuation` — use this before starting a fresh session.
    private func teardownLocked() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

}

package enum AppleSpeechError: LocalizedError {
    case noAudioFile
    case notAuthorized

    package var errorDescription: String? {
        switch self {
        case .noAudioFile: return L("error.no_audio_file")
        case .notAuthorized: return L("error.speech_not_authorized")
        }
    }
}
