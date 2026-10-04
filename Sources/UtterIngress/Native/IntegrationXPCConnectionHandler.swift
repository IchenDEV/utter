import UtterContracts
import Foundation

@MainActor
final class IntegrationXPCConnectionHandler: NSObject, OpenTypeXPCProtocol {
    private let work = IngressTasks()
    private var closed = false
    private var disconnectTask: Task<Void, Never>?
    private struct EventSubscription {
        let sessionID: UUID
        let subscriberID: UUID
        let connection: NSXPCConnection
    }

    private let log: Log
    private let clientID: String
    private let service: any InputSessionService
    private var subscriptions: [UUID: EventSubscription] = [:]

    init(clientID: String, service: any InputSessionService, log: Log) {
        self.log = log
        self.clientID = clientID
        self.service = service
    }

    nonisolated func createSession(_ requestData: Data, with reply: @escaping (Data?, Data?) -> Void) {
        enqueue {
            await self.reply(reply) {
                let request = try JSONDecoder.integration.decode(InputSessionRequest.self, from: requestData)
                return try await self.service.createSession(request, clientID: self.clientID)
            }
        }
    }

    nonisolated func startRecording(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void) {
        enqueue {
            await self.reply(reply) {
                let id = try Self.uuid(sessionID)
                try await self.service.startRecording(sessionID: id, clientID: self.clientID)
                guard let session = try self.service.session(id, clientID: self.clientID) else {
                    throw IntegrationError.sessionNotFound
                }
                return session
            }
        }
    }

    nonisolated func stopRecording(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void) {
        enqueue {
            await self.reply(reply) {
                try await self.service.stopRecording(
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
        enqueue {
            await self.reply(reply) {
                let url = try Self.writeAudioData(audioData, fileExtension: fileExtension)
                defer { try? FileManager.default.removeItem(at: url) }
                return try await self.service.processAudioFile(
                    sessionID: try Self.uuid(sessionID),
                    clientID: self.clientID,
                    audioURL: url
                )
            }
        }
    }

    nonisolated func cancel(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void) {
        enqueue {
            await self.reply(reply) {
                let id = try Self.uuid(sessionID)
                try await self.service.cancel(sessionID: id, clientID: self.clientID)
                return try self.service.session(id, clientID: self.clientID)
            }
        }
    }

    nonisolated func snapshotEvents(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void) {
        enqueue {
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
        enqueue {
            do {
                let id = try Self.uuid(sessionID)
                let connection = NSXPCConnection(listenerEndpoint: endpoint)
                connection.remoteObjectInterface = NSXPCInterface(with: OpenTypeXPCEventSink.self)
                connection.resume()
                let sink = connection.remoteObjectProxyWithErrorHandler { error in
                    self.log.error("[IntegrationXPC] event sink failed: \(error.localizedDescription)")
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
        enqueue {
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
        guard !closed else { return }
        closed = true
        work.revoke()
        if let id = service.revokeSession(clientID: clientID) {
            disconnectTask = Task { await service.drainSession(sessionID: id, clientID: clientID) }
        }
        for subscription in subscriptions.values {
            service.unsubscribeEvents(
                sessionID: subscription.sessionID,
                subscriberID: subscription.subscriberID
            )
            subscription.connection.invalidate()
        }
        subscriptions.removeAll()
    }

    func close() async {
        invalidate()
        await disconnectTask?.value
        await work.close()
    }

    private nonisolated func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        Task { @MainActor in self.work.launch(operation) }
    }

    private func reply<T: Encodable>(
        _ reply: @escaping (Data?, Data?) -> Void,
        operation: () async throws -> T
    ) async {
        do {
            guard !closed, !Task.isCancelled else { throw CancellationError() }
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
