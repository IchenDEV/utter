import Foundation

@MainActor
extension InputSessionCoordinator {
    func reserve(sessionID: UUID, clientID: String) throws -> InputSession {
        guard let session = try service.session(sessionID, clientID: clientID) else {
            throw IntegrationError.sessionNotFound
        }
        guard session.state == .created else { throw IntegrationError.invalidSessionState }
        let reservation = try ownership.acquire()
        lease = reservation
        owner = (sessionID, clientID)
        requestSettings = VoiceInputSettings(
            settings: settings,
            inputLanguage: session.request.language,
            bundleIdentifier: service.integrationClient(id: clientID)?.bundleIdentifier
        )
        return session
    }

    func checkCurrent() throws {
        guard let lease else { throw CancellationError() }
        try ownership.check(lease)
    }

    func loadSpeechEngine() async throws -> any SpeechEngine {
        let engine: (any SpeechEngine)?
        if let engineLoader {
            engine = await engineLoader(settings)
        } else {
            engine = await engineProvider.engine(settings: settings, selection: requestSettings?.speech)
        }
        try checkCurrent()
        guard let engine, engine.isReady else { throw IntegrationError.modelNotReady }
        return engine
    }

    func runOperation<Value>(
        keepRecording: Bool = false,
        _ operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        guard let lease, let owner, cancelOperation == nil else {
            throw IntegrationError.invalidSessionState
        }
        let task = Task { @MainActor in
            try self.ownership.check(lease)
            return try await operation()
        }
        cancelOperation = { task.cancel() }
        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try ownership.check(lease)
            cancelOperation = nil
            if !keepRecording { release(lease) }
            return value
        } catch {
            cancelOperation = nil
            release(lease)
            let failure = (error as? IntegrationError) ?? .operationFailed
            if error is CancellationError || Task.isCancelled {
                try? await service.cancel(sessionID: owner.sessionID, clientID: owner.clientID)
            } else {
                try? await service.failSession(sessionID: owner.sessionID, clientID: owner.clientID, error: failure)
            }
            throw error
        }
    }

    func cancelOwnedWork() {
        guard let lease else { return }
        ownership.cancel(lease)
        activeSession?.engine.cancelListening()
        activeSession?.screenContextTask?.cancel()
        if let cancelOperation {
            cancelOperation()
        } else {
            release(lease)
        }
    }

    private func release(_ reservation: UUID) {
        guard lease == reservation else { return }
        activeSession?.engine.cancelListening()
        activeSession?.screenContextTask?.cancel()
        finishCapture()
        activeSession = nil
        requestSettings = nil
        pendingHistory = nil
        owner = nil
        lease = nil
        ownership.release(reservation)
    }
}
