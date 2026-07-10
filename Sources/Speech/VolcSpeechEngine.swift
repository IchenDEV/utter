import Foundation
import AVFoundation

final class VolcSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let appKey: String
    private let accessKey: String
    private let resourceId: String

    private(set) var isReady: Bool
    private typealias Connection = (session: URLSession, task: URLSessionWebSocketTask)
    private var streamingSession: VolcStreamingSession?

    private static let endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
    private static let chunkSize = 6400 // ~200ms at 16kHz 16-bit mono
    private static let timeoutSeconds: UInt64 = 30

    init(appKey: String, accessKey: String, resourceId: String) {
        self.appKey = appKey
        self.accessKey = accessKey
        self.resourceId = resourceId
        self.isReady = !appKey.isEmpty && !accessKey.isEmpty && !resourceId.isEmpty
    }

    var supportsStreaming: Bool { true }

    func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        guard isReady else { return }
        streamingSession = VolcStreamingSession(
            engine: self,
            language: language,
            partialHandler: onPartialResult
        )
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        streamingSession?.append(buffer)
    }

    func finishListening(audioURL: URL?, language: String?) async throws -> String {
        defer { streamingSession = nil }
        if let streamingSession {
            let outcome = await streamingSession.finishLivePreview()
            return try await StreamingTranscriptResolver.resolveFinalTranscript(
                engineName: "VolcASR",
                audioURL: audioURL,
                livePreviewText: outcome.livePreviewText,
                metrics: outcome.metrics,
                unitLabel: "bytes"
            ) { [weak self] in
                guard let self else { return "" }
                return try await self.transcribe(audioURL: audioURL, language: language)
            }
        }
        return try await transcribe(audioURL: audioURL, language: language)
    }

    func cancelListening() {
        streamingSession?.cancel()
        streamingSession = nil
    }

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard isReady else { throw VolcASRError.notConfigured }
        guard let url = audioURL else { throw VolcASRError.noAudioFile }

        Log.info("[VolcASR] connecting: endpoint=\(Self.endpoint) resourceId=\(resourceId) appKey=\(appKey.prefix(4))***")

        let t0 = CFAbsoluteTimeGetCurrent()
        let pcmData = try convertToPCM16k(url: url)
        guard !pcmData.isEmpty else { return "" }
        Log.info("[VolcASR] audio converted: \(pcmData.count) bytes PCM 16kHz")

        let text = try await transcribePCMData(pcmData, language: language)

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[VolcASR] transcribed \(text.count) chars in \(String(format: "%.1f", elapsed))s")
        return text
    }

    func transcribePCMData(_ pcmData: Data, language: String?) async throws -> String {
        guard !pcmData.isEmpty else { return "" }

        let connectId = UUID().uuidString
        let conn = try openConnection(connectId: connectId)
        defer { closeConnection(conn) }

        let volcLang = volcLanguage(from: language)
        Log.info("[VolcASR] sending full client request, language=\(volcLang ?? "auto")")
        do {
            try await sendFullClientRequest(conn: conn, language: volcLang)
        } catch {
            Log.error("[VolcASR] send full client request failed: \(error.localizedDescription)")
            throw VolcASRError.handshakeRejected
        }

        Log.info("[VolcASR] waiting for handshake response...")
        do {
            if let handshake = try await receiveResponse(conn: conn), let code = handshake.errorCode {
                Log.error("[VolcASR] handshake error: code=\(code) message=\(handshake.errorMessage ?? "nil")")
                throw VolcASRError.serverError(code: code, message: handshake.errorMessage ?? "Unknown")
            }
        } catch let error as VolcASRError {
            throw error
        } catch {
            Log.error("[VolcASR] handshake failed: \(error.localizedDescription)")
            throw VolcASRError.handshakeRejected
        }
        Log.info("[VolcASR] handshake ok, streaming audio...")

        return try await streamAudioAndCollect(conn: conn, pcmData: pcmData)
    }

    // MARK: - URLSession WebSocket

    private func openConnection(connectId: String) throws -> Connection {
        guard let url = URL(string: Self.endpoint) else {
            throw VolcASRError.invalidEndpoint
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = TimeInterval(Self.timeoutSeconds)
        configuration.timeoutIntervalForResource = TimeInterval(Self.timeoutSeconds)

        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(Self.timeoutSeconds)
        request.setValue(appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectId, forHTTPHeaderField: "X-Api-Connect-Id")

        let task = session.webSocketTask(with: request)
        task.resume()
        Log.info("[VolcASR] WebSocket task resumed")

        return (session, task)
    }

    // MARK: - Send full client request

    private func sendFullClientRequest(conn: Connection, language: String?) async throws {
        var audio: [String: Any] = [
            "format": "pcm",
            "rate": 16000,
            "bits": 16,
            "channel": 1,
            "codec": "raw"
        ]
        if let lang = language { audio["language"] = lang }

        let payload: [String: Any] = [
            "user": ["uid": "opentype_macos"],
            "audio": audio,
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "show_utterances": false
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let message = buildMessage(type: .fullClientRequest, flags: 0x00, serialization: .json, payload: jsonData)
        try await sendMessage(conn: conn, data: message)
    }

    // MARK: - Stream audio

    private func streamAudioAndCollect(conn: Connection, pcmData: Data) async throws -> String {
        let totalChunks = (pcmData.count + Self.chunkSize - 1) / Self.chunkSize
        var lastText = ""

        for i in 0..<totalChunks {
            let start = i * Self.chunkSize
            let end   = min(start + Self.chunkSize, pcmData.count)
            let chunk = pcmData[start..<end]
            let isLast = (i == totalChunks - 1)

            let flags: UInt8 = isLast ? 0x02 : 0x00
            let message = buildMessage(type: .audioOnly, flags: flags, serialization: .none, compression: .none, payload: Data(chunk))
            try await sendMessage(conn: conn, data: message)

            if let resp = try await receiveResponse(conn: conn) {
                if let text = resp.text, !text.isEmpty {
                    lastText = text
                }
                if let code = resp.errorCode {
                    throw VolcASRError.serverError(code: code, message: resp.errorMessage ?? "Unknown")
                }
            }
        }

        return lastText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Receive

    private struct ParsedResponse {
        var text: String?
        var errorCode: Int?
        var errorMessage: String?
        var isFinal: Bool = false
    }

    private func receiveResponse(conn: Connection) async throws -> ParsedResponse? {
        let data = try await receiveMessage(conn: conn)
        return parseResponse(data)
    }

    // MARK: - Binary protocol

    private enum MessageType: UInt8 {
        case fullClientRequest  = 0x01
        case audioOnly          = 0x02
        case fullServerResponse = 0x09
        case errorResponse      = 0x0F
    }

    private enum Serialization: UInt8 {
        case none = 0x00
        case json = 0x01
    }

    private enum PayloadCompression: UInt8 {
        case none = 0x00
        case gzip = 0x01
    }

    private func buildMessage(type: MessageType, flags: UInt8, serialization: Serialization, compression: PayloadCompression = .gzip, payload: Data) -> Data {
        let finalPayload: Data
        let actualCompression: PayloadCompression
        if compression == .gzip, let compressed = Gzip.compress(payload) {
            finalPayload = compressed
            actualCompression = .gzip
        } else {
            finalPayload = payload
            actualCompression = .none
        }

        var data = Data(capacity: 4 + 4 + finalPayload.count)
        data.append(0x11)
        data.append((type.rawValue << 4) | (flags & 0x0F))
        data.append((serialization.rawValue << 4) | actualCompression.rawValue)
        data.append(0x00)
        let size = UInt32(finalPayload.count)
        data.append(UInt8((size >> 24) & 0xFF))
        data.append(UInt8((size >> 16) & 0xFF))
        data.append(UInt8((size >> 8) & 0xFF))
        data.append(UInt8(size & 0xFF))
        data.append(finalPayload)
        return data
    }

    private func parseResponse(_ data: Data) -> ParsedResponse? {
        guard data.count >= 4 else { return nil }

        let msgType        = (data[1] >> 4) & 0x0F
        let flags          = data[1] & 0x0F
        let headerSizeWords = Int(data[0] & 0x0F)
        let headerSize     = headerSizeWords * 4

        if msgType == MessageType.errorResponse.rawValue {
            return parseErrorResponse(data, headerSize: headerSize)
        }

        guard msgType == MessageType.fullServerResponse.rawValue else {
            Log.info("[VolcASR] unexpected message type: 0x\(String(msgType, radix: 16))")
            return nil
        }

        var offset = headerSize
        let hasSequence = (flags & 0x01) != 0
        if hasSequence { offset += 4 }

        guard data.count >= offset + 4 else { return nil }
        let payloadSize = Int(readUInt32(data, at: offset))
        offset += 4

        guard data.count >= offset + payloadSize, payloadSize > 0 else {
            return ParsedResponse(isFinal: (flags & 0x02) != 0)
        }

        let isGzip     = (data[2] & 0x0F) == PayloadCompression.gzip.rawValue
        let rawPayload = Data(data[offset..<(offset + payloadSize)])
        let payloadData: Data
        if isGzip, let decompressed = Gzip.decompress(rawPayload) {
            payloadData = decompressed
        } else {
            payloadData = rawPayload
        }
        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return ParsedResponse(isFinal: (flags & 0x02) != 0)
        }

        // Check for inline error code returned via a normal server response frame
        if let code = json["code"] as? Int, code != 0 {
            let msg = json["message"] as? String ?? "Server error \(code)"
            Log.error("[VolcASR] inline error: code=\(code) message=\(msg)")
            return ParsedResponse(errorCode: code, errorMessage: msg)
        }

        let result = json["result"] as? [String: Any]
        let text   = result?["text"] as? String

        return ParsedResponse(text: text, isFinal: (flags & 0x02) != 0)
    }

    private func parseErrorResponse(_ data: Data, headerSize: Int) -> ParsedResponse {
        var offset = headerSize
        guard data.count >= offset + 4 else {
            return ParsedResponse(errorCode: -1, errorMessage: "Unknown error")
        }
        let errorCode = Int(readUInt32(data, at: offset))
        offset += 4

        guard data.count >= offset + 4 else {
            return ParsedResponse(errorCode: errorCode, errorMessage: "Error \(errorCode)")
        }
        let msgSize = Int(readUInt32(data, at: offset))
        offset += 4

        var errorMsg = "Error \(errorCode)"
        if data.count >= offset + msgSize, msgSize > 0 {
            errorMsg = String(data: Data(data[offset..<(offset + msgSize)]), encoding: .utf8) ?? errorMsg
        }
        return ParsedResponse(errorCode: errorCode, errorMessage: errorMsg)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
        | UInt32(data[offset + 1]) << 16
        | UInt32(data[offset + 2]) << 8
        | UInt32(data[offset + 3])
    }

    // MARK: - WebSocket helpers

    private func closeConnection(_ conn: Connection) {
        conn.task.cancel(with: .normalClosure, reason: nil)
        conn.session.finishTasksAndInvalidate()
    }

    private func sendMessage(conn: Connection, data: Data) async throws {
        do {
            try await runWithTimeout {
                try await conn.task.send(.data(data))
            }
        } catch let error as URLError where error.code == .timedOut {
            throw VolcASRError.timeout
        } catch {
            Log.error("[VolcASR] send failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func receiveMessage(conn: Connection) async throws -> Data {
        do {
            let message = try await runWithTimeout {
                try await conn.task.receive()
            }

            switch message {
            case .data(let data):
                return data
            case .string(let text):
                Log.error("[VolcASR] unexpected text frame: \(text.prefix(200))")
                throw VolcASRError.handshakeRejected
            @unknown default:
                throw VolcASRError.handshakeRejected
            }
        } catch let error as URLError where error.code == .timedOut {
            throw VolcASRError.timeout
        } catch {
            Log.error("[VolcASR] receive failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func runWithTimeout<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
                throw VolcASRError.timeout
            }

            guard let result = try await group.next() else {
                throw VolcASRError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Audio conversion

    private func convertToPCM16k(url: URL) throws -> Data {
        let srcFile  = try AVAudioFile(forReading: url)
        let srcFormat = srcFile.processingFormat

        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw VolcASRError.audioConversionFailed
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw VolcASRError.audioConversionFailed
        }

        let ratio          = 16000.0 / srcFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(srcFile.length) * ratio) + 100
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: estimatedFrames) else {
            throw VolcASRError.audioConversionFailed
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            let frameCount: AVAudioFrameCount = 4096
            guard let readBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try srcFile.read(into: readBuffer)
                if readBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return readBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error { throw error }

        let byteCount = Int(outputBuffer.frameLength) * 2
        guard let int16Data = outputBuffer.int16ChannelData else {
            throw VolcASRError.audioConversionFailed
        }
        return Data(bytes: int16Data[0], count: byteCount)
    }

    // MARK: - Language mapping

    private func volcLanguage(from whisperCode: String?) -> String? {
        switch whisperCode {
        case "zh":  return "zh-CN"
        case "en":  return "en-US"
        case "ja":  return "ja-JP"
        case "ko":  return "ko-KR"
        case "yue": return "yue-CN"
        case "de":  return "de-DE"
        case "fr":  return "fr-FR"
        case "es":  return "es-MX"
        case "pt":  return "pt-BR"
        case "ru":  return "ru-RU"
        case "it":  return "it-IT"
        case "nl":  return "nl-NL"
        case "pl":  return "pl-PL"
        case "tr":  return "tr-TR"
        case "vi":  return "vi-VN"
        case "th":  return "th-TH"
        case "ar":  return "ar-SA"
        case "id":  return "id-ID"
        default:    return nil
        }
    }
}

enum VolcASRError: LocalizedError {
    case notConfigured
    case noAudioFile
    case invalidEndpoint
    case audioConversionFailed
    case timeout
    case handshakeRejected
    case serverError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:        return L("error.volc_not_configured")
        case .noAudioFile:          return L("error.no_audio")
        case .invalidEndpoint:      return L("error.volc_invalid_endpoint")
        case .audioConversionFailed: return L("error.volc_audio_conversion")
        case .timeout:              return L("error.volc_timeout")
        case .handshakeRejected:    return L("error.volc_handshake_rejected")
        case .serverError(let code, let msg): return "ASR Error \(code): \(msg)"
        }
    }
}
