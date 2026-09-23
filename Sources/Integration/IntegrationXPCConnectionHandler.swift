import Foundation

@MainActor
final class IntegrationXPCConnectionHandler: NSObject, OpenTypeXPCProtocol {
    private struct EventSubscription {
        let sessionID: UUID
        let subscriberID: UUID
        let connection: NSXPCConnection
    }

    private let clientID: String
    private let service: OpenTypeService
    private let coordinator: InputSessionCoordinator
    private var subscriptions: [UUID: EventSubscription] = [:]

    init(clientID: String, service: OpenTypeService, coordinator: InputSessionCoordinator) {
        self.clientID = clientID
        self.service = service
        self.coordinator = coordinator
    }

    nonisolated func createSession(_ requestData: Data, with reply: @escaping (Data?, Data?) -> Void) {
        Task { @MainActor in
            await self.reply(reply) {
                let request = try JSONDecoder.integration.decode(InputSessionRequest.self, from: requestData)
                return try await self.service.createSession(request, clientID: self.clientID)
            }
        }
    }

    nonisolated func startRecording(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void) {
        Task { @MainActor in
            await self.reply(reply) {
                let id = try Self.uuid(sessionID)
                try await self.coordinator.startRecording(sessionID: id, clientID: self.clientID)
                guard let session = try self.service.session(id, clientID: self.clientID) else {
                    throw IntegrationError.sessionNotFound
                }
                return session
            }
        }
    }

    nonisolated func stopRecording(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void) {
        Task { @MainActor in
            await self.reply(reply) {
                try await self.coordinator.stopRecording(
                    sessionID: try Self.uuid(sessionID),
                    clientID: self.clientID
                )
            }
        }
    }

    nonisolated func processAudio(
        _ sessionID: String,
        audioData: Data,
        fileExtension: String,
        with reply: @escaping (Data?, Data?) -> Void
    ) {
        Task { @MainActor in
            await self.reply(reply) {
                let url = try Self.writeAudioData(audioData, fileExtension: fileExtension)
                return try await self.coordinator.processAudioFile(
                    sessionID: try Self.uuid(sessionID),
                    clientID: self.clientID,
                    audioURL: url,
                    cleanup: true
                )
            }
        }
    }

    nonisolated func cancel(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void) {
        Task { @MainActor in
            await self.reply(reply) {
                let id = try Self.uuid(sessionID)
                try await self.coordinator.cancel(sessionID: id, clientID: self.clientID)
                return try self.service.session(id, clientID: self.clientID)
            }
        }
    }

    nonisolated func snapshotEvents(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void) {
        Task { @MainActor in
            await self.reply(reply) {
                try self.service.snapshotEvents(
                    sessionID: try Self.uuid(sessionID),
                    clientID: self.clientID
                )
            }
        }
    }

    nonisolated func subscribeEvents(
        _ sessionID: String,
        endpoint: NSXPCListenerEndpoint,
        with reply: @escaping (String?, Data?) -> Void
    ) {
        Task { @MainActor in
            do {
                let id = try Self.uuid(sessionID)
                let connection = NSXPCConnection(listenerEndpoint: endpoint)
                connection.remoteObjectInterface = NSXPCInterface(with: OpenTypeXPCEventSink.self)
                connection.resume()
                let sink = connection.remoteObjectProxyWithErrorHandler { error in
                    Log.error("[IntegrationXPC] event sink failed: \(error.localizedDescription)")
                } as? OpenTypeXPCEventSink

                let subscription = try self.service.subscribeEvents(sessionID: id, clientID: self.clientID) { event in
                    guard let data = try? JSONEncoder.integration.encode(event) else { return }
                    sink?.receiveEvent(data)
                }

                for event in subscription.snapshot {
                    if let data = try? JSONEncoder.integration.encode(event) {
                        sink?.receiveEvent(data)
                    }
                }

                self.subscriptions[subscription.id] = EventSubscription(
                    sessionID: id,
                    subscriberID: subscription.id,
                    connection: connection
                )
                reply(subscription.id.uuidString, nil)
            } catch {
                reply(nil, Self.errorData(error))
            }
        }
    }

    nonisolated func unsubscribeEvents(_ subscriptionID: String) {
        Task { @MainActor in
            guard let id = UUID(uuidString: subscriptionID),
                  let subscription = self.subscriptions[id] else { return }
            self.service.unsubscribeEvents(
                sessionID: subscription.sessionID,
                subscriberID: subscription.subscriberID
            )
            subscription.connection.invalidate()
            self.subscriptions[id] = nil
        }
    }

    func invalidate() {
        coordinator.releaseActiveSessionForShutdown(clientID: clientID)
        for subscription in subscriptions.values {
            service.unsubscribeEvents(
                sessionID: subscription.sessionID,
                subscriberID: subscription.subscriberID
            )
            subscription.connection.invalidate()
        }
        subscriptions.removeAll()
    }

    private func reply<T: Encodable>(
        _ reply: @escaping (Data?, Data?) -> Void,
        operation: () async throws -> T
    ) async {
        do {
            reply(try JSONEncoder.integration.encode(try await operation()), nil)
        } catch {
            reply(nil, Self.errorData(error))
        }
    }

    private nonisolated static func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw IntegrationError.sessionNotFound
        }
        return id
    }

    private nonisolated static func writeAudioData(_ data: Data, fileExtension: String) throws -> URL {
        guard !data.isEmpty else {
            throw IntegrationError.noSpeechDetected
        }
        let ext = fileExtension
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .nonEmpty ?? "wav"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentype_xpc_audio_\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private nonisolated static func errorData(_ error: Error) -> Data {
        let payload: IntegrationError.Payload
        if let error = error as? IntegrationError {
            payload = error.payload
        } else if error is DecodingError {
            payload = IntegrationError.Payload(error: "bad_request", message: "Request body is not valid JSON.")
        } else {
            payload = IntegrationError.operationFailed.payload
        }
        return (try? JSONEncoder.integration.encode(payload)) ?? Data()
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
