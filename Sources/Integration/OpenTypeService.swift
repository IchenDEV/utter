import Foundation

struct IntegrationServiceSettings {
    var developerInterfaceEnabled: Bool
    var httpToken: String

    @MainActor
    static var live: IntegrationServiceSettings {
        IntegrationServiceSettings(
            developerInterfaceEnabled: AppSettings.shared.developerInterfaceEnabled,
            httpToken: AppSettings.shared.developerHTTPToken
        )
    }
}

@MainActor
final class OpenTypeService {
    private typealias EventSubscriber = @MainActor (InputSessionEvent) -> Void

    private var sessions: [UUID: InputSession]
    private var sessionOwners: [UUID: String]
    private var eventsBySession: [UUID: [InputSessionEvent]]
    private var nextSequenceBySession: [UUID: Int]
    private var eventSubscribers: [UUID: [UUID: EventSubscriber]]
    private let settingsProvider: @MainActor () -> IntegrationServiceSettings
    private let registry: IntegrationClientRegistry

    convenience init(registry: IntegrationClientRegistry = IntegrationClientRegistry()) {
        self.init(settingsProvider: { .live }, registry: registry)
    }

    convenience init(settings: IntegrationServiceSettings, registry: IntegrationClientRegistry = IntegrationClientRegistry()) {
        self.init(settingsProvider: { settings }, registry: registry)
    }

    init(
        settingsProvider: @escaping @MainActor () -> IntegrationServiceSettings,
        registry: IntegrationClientRegistry = IntegrationClientRegistry()
    ) {
        self.sessions = [:]
        self.sessionOwners = [:]
        self.eventsBySession = [:]
        self.nextSequenceBySession = [:]
        self.eventSubscribers = [:]
        self.settingsProvider = settingsProvider
        self.registry = registry
    }

    func createSession(_ request: InputSessionRequest, clientID: String) async throws -> InputSession {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard sessions.values.allSatisfy({ $0.state.isTerminal }) else {
            throw IntegrationError.busy
        }

        let now = Date()
        let session = InputSession(
            id: UUID(),
            request: request,
            state: .created,
            createdAt: now,
            updatedAt: now
        )
        sessions[session.id] = session
        sessionOwners[session.id] = clientID
        nextSequenceBySession[session.id] = 1
        appendEvent(.sessionCreated, sessionID: session.id, at: now)
        registry.markUsed(clientID: clientID, at: now)

        return session
    }

    func startRecording(sessionID: UUID, clientID: String) async throws {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard var session = sessions[sessionID] else {
            throw IntegrationError.sessionNotFound
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard session.state == .created else {
            throw IntegrationError.invalidSessionState
        }
        guard !sessions.values.contains(where: { $0.id != sessionID && $0.state == .recording }) else {
            throw IntegrationError.busy
        }

        let now = Date()
        session.state = .recording
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.recordingStarted, sessionID: sessionID, at: now)
    }

    func beginProcessing(sessionID: UUID, clientID: String) async throws {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard var session = sessions[sessionID] else {
            throw IntegrationError.sessionNotFound
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard session.state == .recording || session.state == .created else {
            throw IntegrationError.invalidSessionState
        }

        let now = Date()
        session.state = .processing
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.processingStarted, sessionID: sessionID, at: now)
    }

    func completeSession(sessionID: UUID, clientID: String, finalText: String?) async throws {
        try commitSession(sessionID: sessionID, clientID: clientID, finalText: finalText)
    }

    /// Result and history commit without an await between the terminal-state check and publication.
    func commitSession(sessionID: UUID, clientID: String, finalText: String?, record: () -> Void = {}) throws {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard var session = sessions[sessionID] else {
            throw IntegrationError.sessionNotFound
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard !session.state.isTerminal else {
            throw IntegrationError.invalidSessionState
        }
        guard let finalText = finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !finalText.isEmpty else {
            throw IntegrationError.operationFailed
        }

        let now = Date()
        record()
        session.state = .completed
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.textFinal, sessionID: sessionID, at: now, text: finalText)
        appendEvent(.sessionCompleted, sessionID: sessionID, at: now)
    }

    func failSession(sessionID: UUID, clientID: String, error: IntegrationError) async throws {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard var session = sessions[sessionID] else {
            throw IntegrationError.sessionNotFound
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard !session.state.isTerminal else {
            throw IntegrationError.invalidSessionState
        }

        let now = Date()
        session.state = .failed
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.sessionFailed, sessionID: sessionID, at: now, error: error.payload)
    }

    func emitTranscriptPartial(sessionID: UUID, clientID: String, text: String) throws {
        try appendSessionEvent(.transcriptPartial, sessionID: sessionID, clientID: clientID, text: text)
    }

    func emitTranscriptFinal(sessionID: UUID, clientID: String, text: String) throws {
        try appendSessionEvent(.transcriptFinal, sessionID: sessionID, clientID: clientID, text: text)
    }

    func emitAudioReceived(sessionID: UUID, clientID: String) throws {
        try appendSessionEvent(.audioReceived, sessionID: sessionID, clientID: clientID)
    }

    func cancel(sessionID: UUID, clientID: String) async throws {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard var session = sessions[sessionID] else {
            return
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard !session.state.isTerminal else {
            return
        }

        let now = Date()
        session.state = .cancelled
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.sessionCancelled, sessionID: sessionID, at: now)
    }

    func session(_ id: UUID, clientID: String) throws -> InputSession? {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard let session = sessions[id] else {
            return nil
        }
        try requireOwner(sessionID: id, clientID: clientID)
        return session
    }

    func integrationClient(id clientID: String) -> IntegrationClient? {
        registry.client(id: clientID)
    }

    func snapshotEvents(sessionID: UUID, clientID: String) throws -> [InputSessionEvent] {
        try requireAuthorized(clientID: clientID, capability: .streamEvents)
        guard sessionOwners[sessionID] != nil else {
            return []
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        return eventsBySession[sessionID] ?? []
    }

    func subscribeEvents(
        sessionID: UUID,
        clientID: String,
        onEvent: @escaping @MainActor (InputSessionEvent) -> Void
    ) throws -> (id: UUID, snapshot: [InputSessionEvent]) {
        try requireAuthorized(clientID: clientID, capability: .streamEvents)
        guard sessionOwners[sessionID] != nil else {
            throw IntegrationError.sessionNotFound
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)

        let id = UUID()
        let snapshot = eventsBySession[sessionID] ?? []
        eventSubscribers[sessionID, default: [:]][id] = onEvent
        return (id, snapshot)
    }

    func unsubscribeEvents(sessionID: UUID, subscriberID: UUID) {
        eventSubscribers[sessionID]?[subscriberID] = nil
        if eventSubscribers[sessionID]?.isEmpty == true {
            eventSubscribers[sessionID] = nil
        }
    }

    private func requireAuthorized(clientID: String, capability: IntegrationClient.Capability) throws {
        let settings = settingsProvider()
        guard settings.developerInterfaceEnabled else {
            throw IntegrationError.developerInterfaceDisabled
        }
        if clientID.hasPrefix("http:") {
            let currentLocalHTTPClientID = IntegrationClient.localHTTP(tokenID: settings.httpToken).id
            guard clientID == currentLocalHTTPClientID else {
                throw IntegrationError.unauthorizedClient
            }
        }
        guard registry.isAuthorized(clientID: clientID, capability: capability) else {
            throw IntegrationError.unauthorizedClient
        }
    }

    private func requireOwner(sessionID: UUID, clientID: String) throws {
        guard sessionOwners[sessionID] == clientID else {
            throw IntegrationError.unauthorizedClient
        }
    }

    private func appendSessionEvent(
        _ type: InputSessionEvent.EventType,
        sessionID: UUID,
        clientID: String,
        text: String? = nil
    ) throws {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard let session = sessions[sessionID], !session.state.isTerminal else {
            throw IntegrationError.invalidSessionState
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        appendEvent(type, sessionID: sessionID, at: Date(), text: text)
    }

    private func appendEvent(
        _ type: InputSessionEvent.EventType,
        sessionID: UUID,
        at timestamp: Date,
        text: String? = nil,
        error: IntegrationError.Payload? = nil
    ) {
        let sequence = nextSequenceBySession[sessionID] ?? 1
        let event = InputSessionEvent(
            type: type,
            sessionID: sessionID,
            sequence: sequence,
            timestamp: timestamp,
            text: text,
            error: error
        )
        eventsBySession[sessionID, default: []].append(event)
        nextSequenceBySession[sessionID] = sequence + 1
        if let subscribers = eventSubscribers[sessionID]?.values {
            for subscriber in subscribers {
                subscriber(event)
            }
        }
    }
}
