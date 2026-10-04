import UtterContracts
import Foundation

@MainActor
package final class OpenTypeService: InputSessionService {
    private var closed = false
    let execution: (any SessionExecutionService)?
    private typealias EventSubscriber = @MainActor (InputSessionEvent) -> Void

    var sessions: [UUID: InputSession]
    var sessionOwners: [UUID: String]
    var eventsBySession: [UUID: [InputSessionEvent]]
    var nextSequenceBySession: [UUID: Int]
    private var eventSubscribers: [UUID: [UUID: EventSubscriber]]
    private let settingsProvider: @MainActor () -> IntegrationServiceSettings
    let registry: any IntegrationClientStore
    let notifications: StateNotifications

    package convenience init(settings: IntegrationServiceSettings, registry: any IntegrationClientStore, notifications: StateNotifications? = nil) {
        self.init(settingsProvider: { settings }, registry: registry, notifications: notifications)
    }

    package init(
        settingsProvider: @escaping @MainActor () -> IntegrationServiceSettings,
        registry: any IntegrationClientStore,
        notifications: StateNotifications? = nil,
        execution: (any SessionExecutionService)? = nil
    ) {
        self.execution = execution
        self.notifications = notifications ?? StateNotifications()
        self.sessions = [:]
        self.sessionOwners = [:]
        self.eventsBySession = [:]
        self.nextSequenceBySession = [:]
        self.eventSubscribers = [:]
        self.settingsProvider = settingsProvider
        self.registry = registry
    }

    package func startRecording(sessionID: UUID, clientID: String) async throws {
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

        if let execution {
            try execution.activate(sessionID)
            try await execution.waitForRecording(sessionID)
            return
        }
        let now = Date()
        session.state = .recording
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.recordingStarted, sessionID: sessionID, at: now)
    }

    package func beginProcessing(sessionID: UUID, clientID: String) async throws {
        guard execution == nil else { throw IntegrationError.invalidSessionState }
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

    package func completeSession(sessionID: UUID, clientID: String, finalText: String?) async throws {
        try commitSession(sessionID: sessionID, clientID: clientID, finalText: finalText)
    }

    /// Result and history commit without an await between the terminal-state check and publication.
    package func commitSession(sessionID: UUID, clientID: String, finalText: String?, record: () -> Void = {}) throws {
        guard execution == nil else { throw IntegrationError.invalidSessionState }
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
        session.state = .completed
        session.updatedAt = now
        sessions[sessionID] = session
        notifications.settle {
            appendEvent(.textFinal, sessionID: sessionID, at: now, text: finalText)
            appendEvent(.sessionCompleted, sessionID: sessionID, at: now)
            record()
        }
    }

    package func failSession(sessionID: UUID, clientID: String, error: IntegrationError) async throws {
        guard execution == nil else { throw IntegrationError.invalidSessionState }
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

    package func emitTranscriptPartial(sessionID: UUID, clientID: String, text: String) throws {
        try appendSessionEvent(.transcriptPartial, sessionID: sessionID, clientID: clientID, text: text)
    }

    package func emitTranscriptFinal(sessionID: UUID, clientID: String, text: String) throws {
        try appendSessionEvent(.transcriptFinal, sessionID: sessionID, clientID: clientID, text: text)
    }

    package func emitAudioReceived(sessionID: UUID, clientID: String) throws {
        try appendSessionEvent(.audioReceived, sessionID: sessionID, clientID: clientID)
    }

    package func cancel(sessionID: UUID, clientID: String) async throws {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard var session = sessions[sessionID] else {
            return
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard !session.state.isTerminal else {
            return
        }

        if let execution {
            guard execution.snapshot.id == sessionID else { throw IntegrationError.invalidSessionState }
            execution.cancel(sessionID)
            await execution.stop(sessionID)
            return
        }
        let now = Date()
        session.state = .cancelled
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.sessionCancelled, sessionID: sessionID, at: now)
    }

    package func session(_ id: UUID, clientID: String) throws -> InputSession? {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard let session = sessions[id] else {
            return nil
        }
        try requireOwner(sessionID: id, clientID: clientID)
        return session
    }

    package func integrationClient(id clientID: String) -> IntegrationClient? {
        guard !closed else { return nil }
        return registry.client(id: clientID)
    }

    package func snapshotEvents(sessionID: UUID, clientID: String) throws -> [InputSessionEvent] {
        try requireAuthorized(clientID: clientID, capability: .streamEvents)
        guard sessionOwners[sessionID] != nil else {
            return []
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        return eventsBySession[sessionID] ?? []
    }

    package func subscribeEvents(
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
        eventSubscribers[sessionID, default: [:]][id] = { [weak self] event in
            guard let self else { return }
            guard (try? self.requireAuthorized(clientID: clientID, capability: .streamEvents)) != nil else {
                self.unsubscribeEvents(sessionID: sessionID, subscriberID: id)
                return
            }
            onEvent(event)
        }
        return (id, snapshot)
    }

    package func unsubscribeEvents(sessionID: UUID, subscriberID: UUID) {
        eventSubscribers[sessionID]?[subscriberID] = nil
        if eventSubscribers[sessionID]?.isEmpty == true {
            eventSubscribers[sessionID] = nil
        }
    }

    package func close() {
        closed = true
        eventSubscribers.removeAll()
    }

    func requireAuthorized(clientID: String, capability: IntegrationClient.Capability) throws {
        guard !closed else { throw IntegrationError.developerInterfaceDisabled }
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

    func requireOwner(sessionID: UUID, clientID: String) throws {
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

    func appendEvent(
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
        let subscriberIDs = eventSubscribers[sessionID]?.keys.sorted { $0.uuidString < $1.uuidString } ?? []
        notifications.enqueue { [weak self] in
            for id in subscriberIDs {
                self?.eventSubscribers[sessionID]?[id]?(event)
            }
        }
    }
}
