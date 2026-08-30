import Foundation

enum LocalHTTPAuthorization {
    case success(IntegrationClient)
    case failure(IntegrationHTTPResponse)
}

@MainActor
struct IntegrationHTTPDispatcher {
    let service: OpenTypeService
    let coordinator: InputSessionCoordinator
    let registry: IntegrationClientRegistry
    let settingsProvider: @MainActor () -> IntegrationServiceSettings

    func dispatch(_ request: IntegrationHTTPRequest) async -> IntegrationHTTPResponse {
        let authorizedClient = authorizeLocalHTTPClient(for: request)
        guard case let .success(client) = authorizedClient else {
            if case let .failure(response) = authorizedClient {
                return response
            }
            return Self.internalServerError()
        }

        do {
            switch IntegrationHTTPRoute.match(method: request.method, path: request.path) {
            case .createSession:
                let sessionRequest = try decodeSessionRequest(from: request.body)
                let session = try await service.createSession(sessionRequest, clientID: client.id)
                return IntegrationHTTPResponse.json(session, statusCode: 201)
            case let .events(sessionID):
                let events = try service.snapshotEvents(sessionID: sessionID, clientID: client.id)
                let body = try IntegrationSSE.encode(events)
                return IntegrationHTTPResponse(
                    statusCode: 200,
                    reason: "OK",
                    headers: [
                        "Cache-Control": "no-cache",
                        "Content-Type": "text/event-stream"
                    ],
                    body: body
                )
            case let .submitAudio(sessionID):
                let audioURL = try writeAudioUpload(request)
                let result = try await coordinator.processAudioFile(
                    sessionID: sessionID,
                    clientID: client.id,
                    audioURL: audioURL,
                    cleanup: true
                )
                return IntegrationHTTPResponse.json(result, statusCode: 200)
            case let .startRecording(sessionID):
                try await coordinator.startRecording(sessionID: sessionID, clientID: client.id)
                guard let session = try service.session(sessionID, clientID: client.id) else {
                    return IntegrationHTTPResponse.notFound()
                }
                return IntegrationHTTPResponse.json(session, statusCode: 202)
            case let .stopRecording(sessionID):
                let result = try await coordinator.stopRecording(sessionID: sessionID, clientID: client.id)
                return IntegrationHTTPResponse.json(result, statusCode: 200)
            case let .cancel(sessionID):
                guard try service.session(sessionID, clientID: client.id) != nil else {
                    return IntegrationHTTPResponse(statusCode: 204, reason: "No Content", headers: [:], body: Data())
                }
                try await coordinator.cancel(sessionID: sessionID, clientID: client.id)
                guard let session = try service.session(sessionID, clientID: client.id) else {
                    return IntegrationHTTPResponse.notFound()
                }
                return IntegrationHTTPResponse.json(session, statusCode: 202)
            case .notFound:
                return IntegrationHTTPResponse.notFound()
            }
        } catch let error as IntegrationError {
            return IntegrationHTTPResponse.error(error, statusCode: Self.statusCode(for: error))
        } catch is DecodingError {
            return Self.badRequest(message: "Request body is not valid JSON.")
        } catch {
            return Self.internalServerError()
        }
    }

    func authorizeLocalHTTPClient(
        for request: IntegrationHTTPRequest
    ) -> LocalHTTPAuthorization {
        let settings = settingsProvider()
        guard settings.developerInterfaceEnabled else {
            return .failure(IntegrationHTTPResponse.error(.developerInterfaceDisabled, statusCode: 401))
        }
        guard let token = request.bearerToken, token == settings.httpToken else {
            return .failure(IntegrationHTTPResponse.error(.unauthorizedClient, statusCode: 401))
        }

        if let clientID = request.header("X-OpenType-Client-ID") {
            guard let client = registry.client(id: clientID), client.transport != .http else {
                return .failure(IntegrationHTTPResponse.error(.unauthorizedClient, statusCode: 401))
            }
            return .success(client)
        }

        let client = IntegrationClient.localHTTP(tokenID: token)
        registry.approve(client)
        return .success(client)
    }

    nonisolated static func statusCode(for error: Error) -> Int {
        guard let error = error as? IntegrationError else {
            return 500
        }
        switch error {
        case .developerInterfaceDisabled, .unauthorizedClient:
            return 401
        case .busy, .invalidSessionState, .sessionCancelled:
            return 409
        case .sessionNotFound:
            return 404
        case .permissionDenied, .modelNotReady, .noSpeechDetected:
            return 400
        case .operationFailed, .operationFailedWithMessage:
            return 500
        }
    }

    private func decodeSessionRequest(from body: Data) throws -> InputSessionRequest {
        guard !body.isEmpty else {
            return InputSessionRequest(mode: nil, language: nil, useScreenContext: nil)
        }
        return try JSONDecoder.integration.decode(InputSessionRequest.self, from: body)
    }

    private func writeAudioUpload(_ request: IntegrationHTTPRequest) throws -> URL {
        guard !request.body.isEmpty else {
            throw IntegrationError.noSpeechDetected
        }
        let ext = request.header("X-OpenType-Audio-Extension")?
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .nonEmpty ?? "wav"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentype_upload_\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try request.body.write(to: url, options: [.atomic])
        return url
    }

    private static func badRequest(message: String) -> IntegrationHTTPResponse {
        IntegrationHTTPResponse.json(
            IntegrationError.Payload(error: "bad_request", message: message),
            statusCode: 400
        )
    }

    private static func internalServerError() -> IntegrationHTTPResponse {
        IntegrationHTTPResponse.json(
            IntegrationError.Payload(error: "internal_server_error", message: "Internal server error."),
            statusCode: 500
        )
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
