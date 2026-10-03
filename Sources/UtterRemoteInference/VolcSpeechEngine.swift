import UtterMediaContracts
import UtterContracts
import Foundation
import AVFoundation

package final class VolcSpeechEngine: SpeechEngine, @unchecked Sendable {
    let connectionLock = NSLock()
    var connections: [ObjectIdentifier: Connection] = [:]
    var drainWaiters: [CheckedContinuation<Void, Never>] = []
    var closed = false
    var retiredStreams: [VolcStreamingSession] = []
    let log: Log
    let appKey: String
    let accessKey: String
    let resourceId: String

    package private(set) var isReady: Bool
    typealias Connection = (session: URLSession, task: URLSessionWebSocketTask)
    package var streamingSession: VolcStreamingSession?
    let recognitionContextLock = NSLock()
    package var recognitionContext = SpeechRecognitionContext.empty

    static let endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
    static let chunkSize = 6400 // ~200ms at 16kHz 16-bit mono
    static let timeoutSeconds: UInt64 = 30
    /// The 双向流式 endpoint's direct hotword context budget is documented as
    /// 100 tokens, so keep the list short and bounded well below that.
    package static let maximumHotwordCount = 100
    package static let maximumHotwordCharacters = 300

    package init(appKey: String, accessKey: String, resourceId: String, log: Log) {
        self.log = log
        self.appKey = appKey
        self.accessKey = accessKey
        self.resourceId = resourceId
        self.isReady = !appKey.isEmpty && !accessKey.isEmpty && !resourceId.isEmpty
    }

    package var supportsStreaming: Bool { true }

    package func configureRecognition(context: SpeechRecognitionContext) {
        recognitionContextLock.lock()
        recognitionContext = context
        recognitionContextLock.unlock()
    }

    package func recognitionContextSnapshot() -> SpeechRecognitionContext {
        recognitionContextLock.lock()
        defer { recognitionContextLock.unlock() }
        return recognitionContext
    }

    package func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        guard isReady else { return }
        streamingSession = VolcStreamingSession(
            engine: self,
            language: language,
            partialHandler: onPartialResult, log: log
        )
    }

    package func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        streamingSession?.append(buffer)
    }

    package func finishListening(audioURL: URL?, language: String?) async throws -> String {
        defer { streamingSession = nil }
        if let streamingSession {
            let outcome = await streamingSession.finishLivePreview()
            return try await StreamingTranscriptResolver.resolveFinalTranscript(
                engineName: "VolcASR",
                audioURL: audioURL,
                livePreviewText: outcome.livePreviewText,
                metrics: outcome.metrics,
                unitLabel: "bytes", log: log
            ) { [weak self] in
                guard let self else { return "" }
                return try await self.transcribe(audioURL: audioURL, language: language)
            }
        }
        return try await transcribe(audioURL: audioURL, language: language)
    }

    package func cancelListening() {
        if let streamingSession { retiredStreams.append(streamingSession) }
        streamingSession?.cancel()
        streamingSession = nil
    }

    package func transcribe(audioURL: URL?, language: String?) async throws -> String {
        try Task.checkCancellation()
        guard connectionLock.withLock({ !closed }), isReady else { throw VolcASRError.notConfigured }
        guard let url = audioURL else { throw VolcASRError.noAudioFile }

        log.info("[VolcASR] connecting: endpoint=\(Self.endpoint) resourceId=\(resourceId) appKey=\(appKey.prefix(4))***")

        let t0 = CFAbsoluteTimeGetCurrent()
        let pcmData = try convertToPCM16k(url: url)
        guard !pcmData.isEmpty else { return "" }
        log.info("[VolcASR] audio converted: \(pcmData.count) bytes PCM 16kHz")

        let text = try await transcribePCMData(pcmData, language: language)

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        log.info("[VolcASR] transcribed \(text.count) chars in \(String(format: "%.1f", elapsed))s")
        return text
    }

    package func transcribePCMData(_ pcmData: Data, language: String?) async throws -> String {
        try Task.checkCancellation()
        guard connectionLock.withLock({ !closed }) else { throw CancellationError() }
        guard !pcmData.isEmpty else { return "" }

        let connectId = UUID().uuidString
        let conn = try openConnection(connectId: connectId)
        defer { closeConnection(conn) }

        let volcLang = volcLanguage(from: language)
        log.info("[VolcASR] sending full client request, language=\(volcLang ?? "auto")")
        do {
            try await sendFullClientRequest(conn: conn, language: volcLang)
        } catch {
            log.error("[VolcASR] send full client request failed: \(error.localizedDescription)")
            throw VolcASRError.handshakeRejected
        }

        log.info("[VolcASR] waiting for handshake response...")
        do {
            if let handshake = try await receiveResponse(conn: conn), let code = handshake.errorCode {
                log.error("[VolcASR] handshake error: code=\(code) message=\(handshake.errorMessage ?? "nil")")
                throw VolcASRError.serverError(code: code, message: handshake.errorMessage ?? "Unknown")
            }
        } catch let error as VolcASRError {
            throw error
        } catch {
            log.error("[VolcASR] handshake failed: \(error.localizedDescription)")
            throw VolcASRError.handshakeRejected
        }
        log.info("[VolcASR] handshake ok, streaming audio...")

        let result = try await streamAudioAndCollect(conn: conn, pcmData: pcmData)
        try Task.checkCancellation()
        guard connectionLock.withLock({ !closed }) else { throw CancellationError() }
        return result
    }

    package func shutdown() async {
        let active = connectionLock.withLock { () -> [Connection] in
            closed = true
            return Array(connections.values)
        }
        for connection in active { connection.session.invalidateAndCancel() }
        if let streamingSession { await streamingSession.shutdown() }
        for stream in retiredStreams { await stream.shutdown() }
        retiredStreams.removeAll()
        streamingSession = nil
        await withCheckedContinuation { continuation in
            let drained = connectionLock.withLock { () -> Bool in
                guard !connections.isEmpty else { return true }
                drainWaiters.append(continuation)
                return false
            }
            if drained { continuation.resume() }
        }
    }
}
