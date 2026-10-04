import Foundation
import UtterContracts

@MainActor
package final class SessionDriver: SessionExecutionService {
    private struct Active {
        let intent: SessionIntent
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
    private var admittedIDs: Set<UUID> = []
    private var observers: [UUID: (SessionExecutionSnapshot) -> Void] = [:]
    package private(set) var snapshot = SessionExecutionSnapshot()

    package init(workflows: any SessionWorkflowFactory, history: any HistoryService, notifications: StateNotifications, isReady: @escaping () -> Bool = { true }) {
        self.isReady = isReady
        self.workflows = workflows
        self.history = history
        self.notifications = notifications
    }

    package func start(_ intent: SessionIntent) throws {
        guard !closed, isReady() else { throw IntegrationError.developerInterfaceDisabled }
        guard active == nil, !reserving, !settling else { throw IntegrationError.busy }
        guard !admittedIDs.contains(intent.id) else { throw IntegrationError.invalidSessionState }
        reserving = true
        defer { reserving = false }
        let job = try workflows.make(intent)
        let control = SessionControl(isCurrent: { [weak self] in
            self?.active?.intent.id == intent.id && self?.closed == false && self?.isReady() == true && self?.active?.task.isCancelled == false
        }, update: { [weak self] phase, transcript in self?.update(intent.id, phase: phase, transcript: transcript) })
        let task = Task { [self] in
            let result: Result<SessionCompletion, Error>
            do {
                try Task.checkCancellation()
                result = .success(try await job.run(control: control))
            }
            catch { result = .failure(error) }
            await job.close()
            finish(intent, result: result)
        }
        admittedIDs.insert(intent.id)
        active = Active(intent: intent, job: job, control: control, task: task)
        publish(SessionExecutionSnapshot(id: intent.id, phase: .preparing, isBusy: true))
    }

    package func stop() async {
        guard let active else { return }
        if snapshot.phase == .preparing { cancel() }
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

    private func update(_ id: UUID, phase: SessionExecutionPhase, transcript: String) {
        guard let active, active.intent.id == id, active.control.isCurrent else { return }
        guard [.recording, .transcribing, .processing, .delivering].contains(phase) else { return }
        publish(SessionExecutionSnapshot(id: id, phase: phase, transcript: transcript, isBusy: true))
    }

    private func finish(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {
        guard active?.intent.id == intent.id else { return }
        settling = true
        notifications.settle {
            active = nil
            switch result {
            case .success(let completion) where completion.accepted:
                snapshot = SessionExecutionSnapshot(id: intent.id, phase: .completed,
                    transcript: completion.transcript, text: completion.text)
                if let record = completion.record {
                    history.addRecord(InputRecord(id: intent.id, date: record.date, rawText: record.rawText,
                        processedText: record.processedText, wasProcessed: record.wasProcessed,
                        context: record.context, userFinalText: record.userFinalText, formatKind: record.formatKind))
                }
            case .success(let completion):
                snapshot = SessionExecutionSnapshot(id: intent.id, phase: .failed,
                    transcript: completion.transcript, text: completion.text)
            case .failure(let error):
                snapshot = SessionExecutionSnapshot(id: intent.id,
                    phase: error is CancellationError ? .cancelled : .failed, error: error.localizedDescription)
            }
            workflows.settle(intent, result: result)
            settling = false
            enqueueSnapshot()
        }
    }

    private func publish(_ value: SessionExecutionSnapshot) {
        snapshot = value
        enqueueSnapshot()
    }
    private func enqueueSnapshot() {
        let value = snapshot
        for id in observers.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            notifications.enqueue { [weak self] in self?.observers[id]?(value) }
        }
    }
}
