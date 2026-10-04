import Foundation
import UtterContracts

@MainActor
package final class SessionDriver: SessionExecutionService {
    private struct Active {
        var intent: SessionIntent
        let job: any SessionJob
        let control: SessionControl
        let task: Task<Void, Never>
    }
    private let workflows: any SessionWorkflowFactory
    private let history: any HistoryService
    private let notifications: StateNotifications
    private let isReady: () -> Bool
    private var active: Active?
    private var closed = false
    private var reserving = false
    private var settling = false
    private var terminalFailures: [UUID: Error] = [:]
    private var terminalSnapshots: [UUID: SessionExecutionSnapshot] = [:]
    private var admittedIDs: Set<UUID> = []
    private var progressObservers: [UUID: (SessionIntent, SessionExecutionSnapshot) -> Void] = [:]
    private var settlementObservers: [UUID: (SessionIntent, Result<SessionCompletion, Error>) -> Void] = [:]
    private var observers: [UUID: (SessionExecutionSnapshot) -> Void] = [:]
    package private(set) var snapshot = SessionExecutionSnapshot()

    package init(workflows: any SessionWorkflowFactory, history: any HistoryService, notifications: StateNotifications, isReady: @escaping () -> Bool = { true }) {
        self.isReady = isReady
        self.workflows = workflows
        self.history = history
        self.notifications = notifications
    }

    package func reserve(_ intent: SessionIntent) throws { try admit(intent, activate: false) }

    package func start(_ intent: SessionIntent) throws { try admit(intent, activate: true) }

    package func activate(_ id: UUID, input: SessionInput?) throws {
        guard var active, active.intent.id == id, snapshot.phase == .created else { throw IntegrationError.invalidSessionState }
        guard !closed, isReady(), active.control.isCurrent else { throw CancellationError() }
        let source = input ?? (active.intent.input == .unselected ? .local : active.intent.input)
        guard source != .unselected else { throw IntegrationError.invalidSessionState }
        if active.intent.input == .unselected {
            try active.job.bind(input: source)
            active.intent = SessionIntent(id: id, clientID: active.intent.clientID, input: source,
                request: active.intent.request, mode: active.intent.mode, operation: active.intent.operation)
            self.active = active
        } else if source != active.intent.input {
            throw IntegrationError.invalidSessionState
        }
        workflows.willActivate(active.intent)
        active.control.activate()
        publish(SessionExecutionSnapshot(id: id, phase: .preparing, isBusy: true))
    }

    package func waitForRecording(_ id: UUID) async throws {
        _ = try await waitForPhase(id, recording: true)
    }

    package func waitForCompletion(_ id: UUID) async throws -> SessionExecutionSnapshot {
        try await waitForPhase(id, recording: false)
    }

    private func waitForPhase(_ id: UUID, recording: Bool) async throws -> SessionExecutionSnapshot {
        guard let initial = terminalSnapshots[id] ?? (snapshot.id == id ? snapshot : nil) else {
            throw IntegrationError.invalidSessionState
        }
        let (stream, continuation) = AsyncStream<SessionExecutionSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observation = observe { value in
            if value.id == id { continuation.yield(value) }
        }
        defer { removeObserver(observation); continuation.finish() }
        continuation.yield(initial)
        for await value in stream {
            if Task.isCancelled { break }
            switch value.phase {
            case .completed: return value
            case .recording, .transcribing, .processing, .delivering: if recording { return value }
            case .failed: throw terminalFailures[id] ?? IntegrationError.operationFailed
            case .cancelled: throw CancellationError()
            default: continue
            }
        }
        if active?.intent.id == id {
            cancel()
            await stop()
        }
        throw CancellationError()
    }

    private func admit(_ intent: SessionIntent, activate: Bool) throws {
        guard !closed, isReady() else { throw IntegrationError.developerInterfaceDisabled }
        guard active == nil, !reserving, !settling else { throw IntegrationError.busy }
        guard !admittedIDs.contains(intent.id) else { throw IntegrationError.invalidSessionState }
        reserving = true
        defer { reserving = false }
        let job = try workflows.make(intent)
        if activate, intent.input == .unselected { try job.bind(input: .local) }
        let control = SessionControl(isCurrent: { [weak self] in
            self?.active?.intent.id == intent.id && self?.closed == false && self?.isReady() == true && self?.active?.task.isCancelled == false
        }, cancel: { [weak self] in self?.cancel() }, update: { [weak self] phase, transcript in self?.update(intent.id, phase: phase, transcript: transcript) })
        let task = Task { [self] in
            let result: Result<SessionCompletion, Error>
            do {
                try await control.waitForActivation()
                result = .success(try await job.run(control: control))
            }
            catch { result = .failure(error) }
            await job.close()
            finish(intent, result: result)
        }
        admittedIDs.insert(intent.id)
        active = Active(intent: intent, job: job, control: control, task: task)
        job.attach(control: control)
        if activate { workflows.willActivate(intent); control.activate() }
        publish(SessionExecutionSnapshot(id: intent.id, phase: activate ? .preparing : .created, isBusy: true))
    }

    package func stop() async {
        guard let active else { return }
        if snapshot.phase == .created || snapshot.phase == .preparing { cancel() }
        else { active.control.stop() }
        await withTaskCancellationHandler {
            await active.task.value
        } onCancel: { active.task.cancel() }
    }

    package func cancel() {
        guard let active else { return }
        active.control.revoke()
        active.job.revoke()
        active.task.cancel()
    }

    package func revoke() {
        closed = true
        observers.removeAll()
        cancel()
    }
    package func close() async {
        revoke()
        if let active { await active.task.value }
    }

    package func observe(_ callback: @escaping (SessionExecutionSnapshot) -> Void) -> UUID {
        let id = UUID()
        if !closed { observers[id] = callback }
        return id
    }
    package func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    package func observeProgress(_ callback: @escaping (SessionIntent, SessionExecutionSnapshot) -> Void) -> UUID {
        let id = UUID()
        if !closed { progressObservers[id] = callback }
        return id
    }
    package func removeProgressObserver(_ id: UUID) { progressObservers.removeValue(forKey: id) }

    package func observeSettlement(_ callback: @escaping (SessionIntent, Result<SessionCompletion, Error>) -> Void) -> UUID {
        let id = UUID()
        if !closed { settlementObservers[id] = callback }
        return id
    }
    package func removeSettlementObserver(_ id: UUID) { settlementObservers.removeValue(forKey: id) }

    private func update(_ id: UUID, phase: SessionExecutionPhase, transcript: String) {
        guard let active, active.intent.id == id, active.control.isCurrent else { return }
        guard [.recording, .transcribing, .processing, .delivering].contains(phase) else { return }
        publish(SessionExecutionSnapshot(id: id, phase: phase, transcript: transcript, isBusy: true))
    }

    private func finish(_ original: SessionIntent, result: Result<SessionCompletion, Error>) {
        guard let intent = active?.intent, intent.id == original.id else { return }
        settling = true
        notifications.settle {
            active = nil
            switch result {
            case .success(let completion) where completion.accepted:
                snapshot = SessionExecutionSnapshot(id: intent.id, phase: .completed,
                    transcript: completion.transcript, text: completion.text, deliveryStatus: completion.acceptance.deliveryStatus)
            case .success(let completion):
                snapshot = SessionExecutionSnapshot(id: intent.id, phase: .failed,
                    transcript: completion.transcript, text: completion.text,
                    error: completion.acceptance.deliveryReason,
                    deliveryStatus: completion.acceptance.deliveryStatus)
            case .failure(let error):
                terminalFailures[intent.id] = error
                snapshot = SessionExecutionSnapshot(id: intent.id,
                    phase: error is CancellationError ? .cancelled : .failed, error: error.localizedDescription)
            }
            terminalSnapshots[intent.id] = snapshot
            for (id, callback) in Array(settlementObservers) where settlementObservers[id] != nil { callback(intent, result) }
            if case .success(let completion) = result {
                if completion.acceptance.deliveryStatus == .inserted, let replacement = completion.historyReplacement {
                    history.replaceRecord(recordID: replacement.recordID, processedText: completion.text,
                        context: replacement.context, formatKind: replacement.formatKind)
                } else if let record = completion.record {
                    history.addRecord(InputRecord(id: intent.id, date: record.date, rawText: record.rawText,
                        processedText: record.processedText, wasProcessed: record.wasProcessed,
                        context: record.context, userFinalText: record.userFinalText, formatKind: record.formatKind,
                        deliveryStatus: completion.acceptance.deliveryStatus))
                }
            }
            workflows.settle(intent, result: result)
            settling = false
            enqueueSnapshot()
        }
    }

    private func publish(_ value: SessionExecutionSnapshot) {
        notifications.settle {
            snapshot = value
            if let intent = active?.intent {
                for (id, callback) in Array(progressObservers) where progressObservers[id] != nil { callback(intent, value) }
            }
            enqueueSnapshot()
        }
    }
    private func enqueueSnapshot() {
        let value = snapshot
        for id in observers.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            notifications.enqueue { [weak self] in self?.observers[id]?(value) }
        }
    }
}
