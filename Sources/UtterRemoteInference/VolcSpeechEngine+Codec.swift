import Foundation
import AVFoundation
import UtterContracts
import UtterMediaContracts

extension VolcSpeechEngine {
    struct ParsedResponse {
        var text: String?
        var errorCode: Int?
        var errorMessage: String?
        var isFinal: Bool = false
    }

    func receiveResponse(conn: Connection) async throws -> ParsedResponse? {
        let data = try await receiveMessage(conn: conn)
        return parseResponse(data)
    }

    // MARK: - Binary protocol

    enum MessageType: UInt8 {
        case fullClientRequest  = 0x01
        case audioOnly          = 0x02
        case fullServerResponse = 0x09
        case errorResponse      = 0x0F
    }

    enum Serialization: UInt8 {
        case none = 0x00
        case json = 0x01
    }

    enum PayloadCompression: UInt8 {
        case none = 0x00
        case gzip = 0x01
    }

    func buildMessage(type: MessageType, flags: UInt8, serialization: Serialization, compression: PayloadCompression = .gzip, payload: Data) -> Data {
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

    func parseResponse(_ data: Data) -> ParsedResponse? {
        guard data.count >= 4 else { return nil }

        let msgType        = (data[1] >> 4) & 0x0F
        let flags          = data[1] & 0x0F
        let headerSizeWords = Int(data[0] & 0x0F)
        let headerSize     = headerSizeWords * 4

        if msgType == MessageType.errorResponse.rawValue {
            return parseErrorResponse(data, headerSize: headerSize)
        }

        guard msgType == MessageType.fullServerResponse.rawValue else {
            log.info("[VolcASR] unexpected message type: 0x\(String(msgType, radix: 16))")
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
            log.error("[VolcASR] inline error: code=\(code) message=\(msg)")
            return ParsedResponse(errorCode: code, errorMessage: msg)
        }

        let result = json["result"] as? [String: Any]
        let text   = result?["text"] as? String

        return ParsedResponse(text: text, isFinal: (flags & 0x02) != 0)
    }

    func parseErrorResponse(_ data: Data, headerSize: Int) -> ParsedResponse {
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

    func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
        | UInt32(data[offset + 1]) << 16
        | UInt32(data[offset + 2]) << 8
        | UInt32(data[offset + 3])
    }

    // MARK: - WebSocket helpers
}
