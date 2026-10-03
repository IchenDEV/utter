import UtterData
import UtterSession
import UtterContracts
import Foundation
import Network

@MainActor
final class IntegrationHTTPServer {
    private let port: Int
    private let service: OpenTypeService
    private let dispatcher: IntegrationHTTPDispatcher
    private let onFailure: ((NWError) -> Void)?
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection]
    private var eventStreams: [ObjectIdentifier: (sessionID: UUID, subscriberID: UUID)]

    init(
        port: Int,
        service: OpenTypeService,
        coordinator: InputSessionCoordinator,
        registry: IntegrationClientRegistry,
        settingsProvider: @escaping @MainActor () -> IntegrationServiceSettings = { .live },
        onFailure: ((NWError) -> Void)? = nil
    ) {
        self.port = port
        self.service = service
        self.dispatcher = IntegrationHTTPDispatcher(
            service: service,
            coordinator: coordinator,
            registry: registry,
            settingsProvider: settingsProvider
        )
        self.onFailure = onFailure
        self.activeConnections = [:]
        self.eventStreams = [:]
    }

    func start() throws {
        guard listener == nil else {
            return
        }
        guard (1...65_535).contains(port), let listenerPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw IntegrationHTTPServerError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: listenerPort)

        let newListener = try NWListener(using: parameters)
        newListener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        newListener.stateUpdateHandler = { [weak self] state in
            if case let .failed(error) = state {
                Task { @MainActor in
                    self?.onFailure?(error)
                }
            }
        }

        listener = newListener
        newListener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
        for stream in eventStreams.values {
            service.unsubscribeEvents(sessionID: stream.sessionID, subscriberID: stream.subscriberID)
        }
        eventStreams.removeAll()
    }

    func dispatch(_ request: IntegrationHTTPRequest) async -> IntegrationHTTPResponse {
        await dispatcher.dispatch(request)
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        activeConnections[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                Task { @MainActor in
                    self?.connectionDidEnd(id)
                }
            default:
                break
            }
        }

        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else {
                    connection.cancel()
                    return
                }
                guard error == nil else {
                    self.send(Self.badRequest(message: "Malformed HTTP request."), on: connection)
                    return
                }

                var nextBuffer = buffer
                if let data {
                    nextBuffer.append(data)
                }

                if Self.hasCompleteRequest(nextBuffer) || isComplete {
                    await self.respond(to: nextBuffer, on: connection)
                } else {
                    self.receive(on: connection, buffer: nextBuffer)
                }
            }
        }
    }

    private func respond(to data: Data, on connection: NWConnection) async {
        guard let request = IntegrationHTTPRequest.parse(from: data) else {
            send(Self.badRequest(message: "Malformed HTTP request."), on: connection)
            return
        }

        if case .events = IntegrationHTTPRoute.match(method: request.method, path: request.path) {
            streamEvents(for: request, on: connection)
            return
        }

        let response = await dispatch(request)
        send(response, on: connection)
    }

    private func send(_ response: IntegrationHTTPResponse, on connection: NWConnection) {
        send(response.serialize(), on: connection, closeAfterSend: true)
    }

    private func send(_ data: Data, on connection: NWConnection, closeAfterSend: Bool) {
        connection.send(content: data, completion: .contentProcessed { _ in
            guard closeAfterSend else { return }
            connection.cancel()
        })
    }

    private func connectionDidEnd(_ id: ObjectIdentifier) {
        activeConnections[id] = nil
        if let stream = eventStreams[id] {
            service.unsubscribeEvents(sessionID: stream.sessionID, subscriberID: stream.subscriberID)
            eventStreams[id] = nil
        }
    }

    private func streamEvents(for request: IntegrationHTTPRequest, on connection: NWConnection) {
        let authorizedClient = dispatcher.authorizeLocalHTTPClient(for: request)
        guard case let .success(client) = authorizedClient else {
            if case let .failure(response) = authorizedClient {
                send(response, on: connection)
            } else {
                send(Self.internalServerError(), on: connection)
            }
            return
        }
        guard case let .events(sessionID) = IntegrationHTTPRoute.match(method: request.method, path: request.path) else {
            send(IntegrationHTTPResponse.notFound(), on: connection)
            return
        }

        do {
            let subscription = try service.subscribeEvents(sessionID: sessionID, clientID: client.id) { [weak self, weak connection] event in
                guard let self, let connection else { return }
                self.sendSSEEvent(event, on: connection)
            }
            let id = ObjectIdentifier(connection)
            eventStreams[id] = (sessionID: sessionID, subscriberID: subscription.id)
            send(sseHeader(), on: connection, closeAfterSend: false)
            sendSSEEvents(subscription.snapshot, on: connection)
        } catch let error as IntegrationError {
            send(IntegrationHTTPResponse.error(error, statusCode: IntegrationHTTPDispatcher.statusCode(for: error)), on: connection)
        } catch {
            send(Self.internalServerError(), on: connection)
        }
    }

    private func sseHeader() -> Data {
        var data = Data()
        append("HTTP/1.1 200 OK\r\n", to: &data)
        append("Cache-Control: no-cache\r\n", to: &data)
        append("Connection: keep-alive\r\n", to: &data)
        append("Content-Type: text/event-stream\r\n", to: &data)
        append("\r\n", to: &data)
        return data
    }

    private func sendSSEEvents(_ events: [InputSessionEvent], on connection: NWConnection) {
        for event in events {
            sendSSEEvent(event, on: connection)
        }
    }

    private func sendSSEEvent(_ event: InputSessionEvent, on connection: NWConnection) {
        guard let data = try? IntegrationSSE.encode(event) else { return }
        send(data, on: connection, closeAfterSend: event.type.closesEventStream)
    }

    private nonisolated static func hasCompleteRequest(_ data: Data) -> Bool {
        let delimiter = Data([13, 10, 13, 10])
        guard let delimiterRange = data.range(of: delimiter) else {
            return false
        }
        guard let head = String(data: data[..<delimiterRange.lowerBound], encoding: .utf8) else {
            return true
        }

        let contentLength = head
            .components(separatedBy: "\r\n")
            .dropFirst()
            .compactMap { line -> Int? in
                guard let colonIndex = line.firstIndex(of: ":") else {
                    return nil
                }
                let name = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.caseInsensitiveCompare("Content-Length") == .orderedSame else {
                    return nil
                }
                let valueStart = line.index(after: colonIndex)
                return Int(line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .first ?? 0

        let bodyLength = data.count - delimiterRange.upperBound
        return bodyLength >= contentLength
    }

    private nonisolated static func badRequest(message: String) -> IntegrationHTTPResponse {
        IntegrationHTTPResponse.json(
            IntegrationError.Payload(error: "bad_request", message: message),
            statusCode: 400
        )
    }

    private nonisolated static func internalServerError() -> IntegrationHTTPResponse {
        IntegrationHTTPResponse.json(
            IntegrationError.Payload(error: "internal_server_error", message: "Internal server error."),
            statusCode: 500
        )
    }

    private nonisolated func append(_ string: String, to data: inout Data) {
        guard let encoded = string.data(using: .utf8) else {
            return
        }
        data.append(encoded)
    }
}

private enum IntegrationHTTPServerError: Error {
    case invalidPort
}
