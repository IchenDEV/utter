import Foundation
import AVFoundation
import UtterContracts
import UtterMediaContracts

extension VolcSpeechEngine {
    // MARK: - URLSession WebSocket

    func openConnection(connectId: String) throws -> Connection {
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
        try connectionLock.withLock {
            guard !closed else {
                session.invalidateAndCancel()
                throw CancellationError()
            }
            connections[ObjectIdentifier(task)] = (session, task)
        }
        task.resume()
        log.info("[VolcASR] WebSocket task resumed")

        return (session, task)
    }

    // MARK: - Send full client request

    func sendFullClientRequest(conn: Connection, language: String?) async throws {
        let hotwords = Self.hotwordContext(
            for: recognitionContextSnapshot().phrases
        )
        let payload = Self.fullClientRequestPayload(
            language: language,
            hotwordContext: hotwords
        )

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let message = buildMessage(type: .fullClientRequest, flags: 0x00, serialization: .json, payload: jsonData)
        try await sendMessage(conn: conn, data: message)
    }

    /// Builds the `request.corpus.context` hotword payload. Volc accepts a JSON
    /// string of `{"hotwords":[{"word": ...}]}`; see the official
    /// 大模型流式语音识别 API `corpus.context` field.
    package static func hotwordContext(for phrases: [String]) -> String? {
        var accepted: [String] = []
        var characterCount = 0
        for phrase in phrases {
            let word = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, accepted.count < maximumHotwordCount else { continue }
            guard characterCount + word.count <= maximumHotwordCharacters else { continue }
            accepted.append(word)
            characterCount += word.count
        }
        guard !accepted.isEmpty else { return nil }

        let payload: [String: Any] = ["hotwords": accepted.map { ["word": $0] }]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    package static func fullClientRequestPayload(
        language: String?,
        hotwordContext: String?
    ) -> [String: Any] {
        var audio: [String: Any] = [
            "format": "pcm",
            "rate": 16000,
            "bits": 16,
            "channel": 1,
            "codec": "raw"
        ]
        if let language { audio["language"] = language }

        var request: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": true,
            "show_utterances": false
        ]
        if let hotwordContext, !hotwordContext.isEmpty {
            request["corpus"] = ["context": hotwordContext]
        }

        return [
            "user": ["uid": "opentype_macos"],
            "audio": audio,
            "request": request
        ]
    }

    // MARK: - Stream audio

    func streamAudioAndCollect(conn: Connection, pcmData: Data) async throws -> String {
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
}
