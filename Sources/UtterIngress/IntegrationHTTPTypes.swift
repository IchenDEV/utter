import UtterContracts
import Foundation

struct IntegrationHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(from data: Data) -> IntegrationHTTPRequest? {
        let delimiter = Data([13, 10, 13, 10])
        guard let delimiterRange = data.range(of: delimiter) else {
            return nil
        }

        let headData = data[..<delimiterRange.lowerBound]
        guard let head = String(data: headData, encoding: .utf8) else {
            return nil
        }

        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else {
                continue
            }

            let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: colonIndex)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                continue
            }
            headers[name] = value
        }

        let bodyStart = delimiterRange.upperBound
        let body = Data(data[bodyStart...])

        return IntegrationHTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: body
        )
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var bearerToken: String? {
        guard let authorization = header("Authorization") else {
            return nil
        }

        let parts = authorization.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].caseInsensitiveCompare("Bearer") == .orderedSame else {
            return nil
        }

        return String(parts[1])
    }
}

enum IntegrationHTTPRoute: Equatable {
    case createSession
    case events(UUID)
    case submitAudio(UUID)
    case startRecording(UUID)
    case stopRecording(UUID)
    case cancel(UUID)
    case notFound

    static func match(method: String, path: String) -> IntegrationHTTPRoute {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if method == "POST", components == ["v1", "sessions"] {
            return .createSession
        }

        guard components.count >= 4,
              components[0] == "v1",
              components[1] == "sessions",
              let sessionID = UUID(uuidString: components[2]) else {
            return .notFound
        }

        if method == "GET", components.count == 4, components[3] == "events" {
            return .events(sessionID)
        }

        if method == "POST", components.count == 4, components[3] == "audio" {
            return .submitAudio(sessionID)
        }

        if method == "POST", components.count == 5, components[3] == "recording" {
            switch components[4] {
            case "start":
                return .startRecording(sessionID)
            case "stop":
                return .stopRecording(sessionID)
            default:
                return .notFound
            }
        }

        if method == "POST", components.count == 4, components[3] == "cancel" {
            return .cancel(sessionID)
        }

        return .notFound
    }
}

struct IntegrationHTTPResponse {
    let statusCode: Int
    let reason: String
    let headers: [String: String]
    let body: Data

    static func json<T: Encodable>(_ value: T, statusCode: Int = 200) -> IntegrationHTTPResponse {
        let body = (try? JSONEncoder.integration.encode(value)) ?? Data()
        return IntegrationHTTPResponse(
            statusCode: statusCode,
            reason: reasonPhrase(for: statusCode),
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    static func error(_ error: IntegrationError, statusCode: Int) -> IntegrationHTTPResponse {
        json(error.payload, statusCode: statusCode)
    }

    static func notFound() -> IntegrationHTTPResponse {
        error(.sessionNotFound, statusCode: 404)
    }

    func serialize() -> Data {
        var data = Data()
        append("HTTP/1.1 \(statusCode) \(reason)\r\n", to: &data)

        var serializedHeaders = headers.filter { key, _ in
            key.caseInsensitiveCompare("Content-Length") != .orderedSame
        }
        serializedHeaders["Content-Length"] = String(body.count)

        for key in serializedHeaders.keys.sorted() {
            guard let value = serializedHeaders[key] else {
                continue
            }
            append("\(key): \(value)\r\n", to: &data)
        }

        append("\r\n", to: &data)
        data.append(body)
        return data
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            return "OK"
        case 201:
            return "Created"
        case 202:
            return "Accepted"
        case 204:
            return "No Content"
        case 400:
            return "Bad Request"
        case 401:
            return "Unauthorized"
        case 404:
            return "Not Found"
        case 409:
            return "Conflict"
        case 500:
            return "Internal Server Error"
        default:
            return "OK"
        }
    }

    private func append(_ string: String, to data: inout Data) {
        guard let encoded = string.data(using: .utf8) else {
            return
        }
        data.append(encoded)
    }
}

enum IntegrationSSE {
    static func encode(_ event: InputSessionEvent) throws -> Data {
        try encode([event])
    }

    static func encode(_ events: [InputSessionEvent]) throws -> Data {
        var data = Data()

        for event in events {
            try append("event: \(event.type.rawValue)\n", to: &data)
            let eventData = try JSONEncoder.integration.encode(event)
            guard let eventJSON = String(data: eventData, encoding: .utf8) else {
                continue
            }
            try append("data: \(eventJSON)\n\n", to: &data)
        }

        return data
    }

    private static func append(_ string: String, to data: inout Data) throws {
        guard let encoded = string.data(using: .utf8) else {
            throw IntegrationSSEError.encodingFailed
        }
        data.append(encoded)
    }
}

private enum IntegrationSSEError: Error {
    case encodingFailed
}
