import Foundation
import UtterContracts
@MainActor
package final class SessionDriver: SessionExecutionService {
    struct Active {
        var intent: SessionIntent
        let job: any SessionJob
        let control: SessionControl
        let task: Task<Void, Never>
        let timing: SessionTiming
    }
    private struct Disclosure {
        let intent: SessionIntent
        let activate: Bool
        let rejection: SelectionEditRemoteDisclosureRequired
        let timeout: Task<Void, Never>
    }
    private let workflows: any SessionWorkflowFactory
    private let history: any HistoryService
    private let notifications: StateNotifications
    private let isReady: () -> Bool
    private let now: () -> Duration
    private(set) var active: Active?
    private var disclosure: Disclosure?
    private(set) var closed = false
    private var reserving = false
    private var settling = false
    private(set) var terminalFailures: [UUID: Error] = [:]
    private(set) var terminalSnapshots: [UUID: SessionExecutionSnapshot] = [:]
    private var admittedIDs: Set<UUID> = []
    var progressObservers: [UUID: (SessionIntent, SessionExecutionSnapshot) -> Void] = [:]
    var settlementObservers: [UUID: (SessionIntent, Result<SessionCompletion, Error>) -> Void] = [:]
    var observers: [UUID: (SessionExecutionSnapshot) -> Void] = [:]
    package private(set) var snapshot = SessionExecutionSnapshot()

    package init(workflows: any SessionWorkflowFactory, history: any HistoryService, notifications: StateNotifications,
                 isReady: @escaping () -> Bool = { true }, now: @escaping () -> Duration = { .seconds(ProcessInfo.processInfo.systemUptime) }) {
        self.isReady = isReady
        self.workflows = workflows
        self.history = history
        self.notifications = notifications
        self.now = now
    }

    package func reserve(_ intent: SessionIntent) throws { try admit(intent, activate: false) }
    package func start(_ intent: SessionIntent) throws { try admit(intent, activate: true) }
    package func promoteToTranslation(_ id: UUID, reason: HotkeyPromotion) -> Bool {
        guard var current = active, current.intent.id == id, current.control.isCurrent, !current.control.isStopped,
              current.intent.clientID == nil,
              snapshot.phase == .recording || (reason == .chordClassification && snapshot.phase == .preparing),
              let mode = current.job.promoteToTranslation() else { return false }
        current.intent = SessionIntent(id: id, clientID: nil, input: current.intent.input, request: current.intent.request,
            mode: mode, operation: current.intent.operation, remoteSelectionConsent: current.intent.remoteSelectionConsent)
        active = current
        update(id, phase: snapshot.phase ?? .preparing, transcript: snapshot.transcript)
        return true
    }

    package func activate(_ id: UUID, input: SessionInput?) throws {
        guard var active, active.intent.id == id, snapshot.phase == .created else { throw IntegrationError.invalidSessionState }
        guard !closed, isReady(), active.control.isCurrent else { throw CancellationError() }
        let source = input ?? (active.intent.input == .unselected ? .local : active.intent.input)
        guard source != .unselected else { throw IntegrationError.invalidSessionState }
        if active.intent.input == .unselected {
            try active.job.bind(input: source)
            active.intent = SessionIntent(id: id, clientID: active.intent.clientID, input: source,
                request: active.intent.request, mode: active.intent.mode, operation: active.intent.operation,
                remoteSelectionConsent: active.intent.remoteSelectionConsent)
            self.active = active
        } else if source != active.intent.input {
            throw IntegrationError.invalidSessionState
        }
        workflows.willActivate(active.intent)
        active.control.activate()
        publish(SessionExecutionSnapshot(id: id, phase: .preparing, isBusy: true))
    }
    private func admit(_ intent: SessionIntent, activate: Bool, allowsDisclosure: Bool = true) throws {
        guard !closed, isReady() else { throw IntegrationError.developerInterfaceDisabled }
        guard active == nil, disclosure == nil, !reserving, !settling else { throw IntegrationError.busy }
        guard !admittedIDs.contains(intent.id) else { throw IntegrationError.invalidSessionState }
        reserving = true
        defer { reserving = false }
        let job: any SessionJob
        do { job = try workflows.make(intent) }
        catch let rejection as SelectionEditRemoteDisclosureRequired {
            guard allowsDisclosure else { throw DeliveryError.invalidTarget }
            let timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, rejection.consent.expiresAt.timeIntervalSinceNow))) }
                catch { return }
                self?.declineRemoteDisclosure(intent.id)
            }
            disclosure = Disclosure(intent: intent, activate: activate, rejection: rejection, timeout: timeout)
            publish(SessionExecutionSnapshot(id: intent.id, phase: .created, isBusy: true, mode: intent.mode,
                remoteDisclosure: rejection.consent))
            return
        }
        if activate, intent.input == .unselected { try job.bind(input: .local) }
        let timing = SessionTiming(now: now)
        let control = SessionControl(isCurrent: { [weak self] in
            self?.active?.intent.id == intent.id && self?.closed == false && self?.isReady() == true && self?.active?.task.isCancelled == false
        }, cancel: { [weak self] in self?.cancel() }, update: { [weak self] phase, transcript in self?.update(intent.id, phase: phase, transcript: transcript) },
        timing: timing, audioLevel: { [weak self] level in self?.updateLevel(intent.id, level: level) })
        let task = Task { [self] in
            let result: Result<SessionCompletion, Error>
            do {
                try await control.waitForActivation()
                result = .success(try await GenerationTimingObservations.$current.withValue(timing.generations) {
                    try await job.run(control: control)
                })
            }
            catch { result = .failure(error) }
            await job.close()
            finish(intent, result: result)
        }
        admittedIDs.insert(intent.id)
        let frozen = SessionIntent(id: intent.id, clientID: intent.clientID, input: intent.input, request: intent.request,
            mode: intent.mode ?? job.presentationMode, operation: intent.operation,
            remoteSelectionConsent: intent.remoteSelectionConsent)
        active = Active(intent: frozen, job: job, control: control, task: task, timing: timing)
        job.attach(control: control)
        if activate { workflows.willActivate(intent); control.activate() }
        publish(SessionExecutionSnapshot(id: intent.id, phase: activate ? .preparing : .created, isBusy: true, mode: frozen.mode))
    }

    @discardableResult
    package func requestStop(_ id: UUID, at timestamp: Duration? = nil) -> Bool {
        if disclosure?.intent.id == id { declineRemoteDisclosure(id); return true }
        guard let active, active.intent.id == id, active.control.isCurrent, !active.control.isStopped,
              [.preparing, .recording].contains(snapshot.phase) else { return false }
        active.timing.stop(at: timestamp)
        active.control.stop()
        return true
    }

    @discardableResult
    package func applySelectionEdit(sessionID: UUID, proposalID: UUID) -> Bool {
        guard let active, active.intent.id == sessionID, snapshot.phase == .processing,
              snapshot.selectionEditProposal?.id == proposalID else { return false }
        return active.control.applySelectionEdit(proposalID)
    }

    package func stop() async {
        if let id = disclosure?.intent.id { declineRemoteDisclosure(id); return }
        guard let active else { return }
        if snapshot.phase == .created { cancel() }
        else { requestStop(active.intent.id) }
        await withTaskCancellationHandler {
            await active.task.value
        } onCancel: { active.task.cancel() }
    }

    package func stop(_ id: UUID) async {
        if disclosure?.intent.id == id { declineRemoteDisclosure(id); return }
        guard active?.intent.id == id else { return }
        await stop()
    }

    package func cancel(_ id: UUID) {
        if disclosure?.intent.id == id { declineRemoteDisclosure(id); return }
        guard active?.intent.id == id else { return }
        cancel()
    }

    package func cancel() {
        if let id = disclosure?.intent.id { declineRemoteDisclosure(id) }
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
        let timeout = disclosure?.timeout
        revoke()
        await timeout?.value
        if let active { await active.task.value }
    }

    package func authorizeRemoteDisclosure(_ intentID: UUID) throws {
        guard let pending = disclosure, pending.intent.id == intentID else { throw IntegrationError.invalidSessionState }
        guard !closed, isReady(), Date() < pending.rejection.consent.expiresAt,
              pending.rejection.isTargetCurrent() else {
            declineRemoteDisclosure(intentID)
            throw DeliveryError.invalidTarget
        }
        pending.timeout.cancel(); disclosure = nil
        let original = pending.intent
        let authorized = SessionIntent(id: original.id, clientID: original.clientID, input: original.input,
            request: original.request, mode: original.mode, operation: original.operation,
            remoteSelectionConsent: pending.rejection.consent)
        do { try admit(authorized, activate: pending.activate, allowsDisclosure: false) }
        catch {
            admittedIDs.insert(intentID); terminalFailures[intentID] = error
            let value = SessionExecutionSnapshot(id: intentID, phase: .failed,
                error: SessionFailurePresentation(error: error).message, mode: original.mode)
            terminalSnapshots[intentID] = value; publish(value)
            throw error
        }
    }

    package func declineRemoteDisclosure(_ intentID: UUID) {
        guard let pending = disclosure, pending.intent.id == intentID else { return }
        pending.timeout.cancel(); disclosure = nil; admittedIDs.insert(intentID)
        let value = SessionExecutionSnapshot(id: intentID, phase: .cancelled, mode: pending.intent.mode)
        terminalSnapshots[intentID] = value; publish(value)
    }

    private func update(_ id: UUID, phase: SessionExecutionPhase, transcript: String) {
        guard let active, active.intent.id == id, active.control.isCurrent else { return }
        guard [.recording, .transcribing, .processing, .delivering].contains(phase) else { return }
        publish(SessionExecutionSnapshot(id: id, phase: phase, transcript: transcript, isBusy: true,
            audioLevel: phase == .recording ? snapshot.audioLevel : 0, mode: active.intent.mode,
            selectionEditProposal: active.control.selectionEditProposal))
    }

    private func updateLevel(_ id: UUID, level: Float) {
        guard active?.intent.id == id, snapshot.phase == .recording else { return }
        publish(SessionExecutionSnapshot(id: id, phase: .recording, transcript: snapshot.transcript,
            isBusy: true, audioLevel: level, mode: active?.intent.mode))
    }

    private func finish(_ original: SessionIntent, result: Result<SessionCompletion, Error>) {
        guard let intent = active?.intent, intent.id == original.id else { return }
        let privateText = hasTemporarySelectionContent(intent)
        let performance = active?.timing.finish(terminal(for: result))
        settling = true
        notifications.settle {
            active = nil
            switch result {
            case .success(let completion) where completion.accepted:
                snapshot = SessionExecutionSnapshot(id: intent.id, phase: .completed,
                    transcript: privateText ? "" : completion.transcript, text: privateText ? "" : completion.text, deliveryStatus: completion.acceptance.deliveryStatus,
                    performance: performance, mode: intent.mode, generationOutcome: completion.generationOutcome)
            case .success(let completion):
                snapshot = SessionExecutionSnapshot(id: intent.id, phase: .failed,
                    transcript: privateText ? "" : completion.transcript, text: privateText ? "" : completion.text,
                    error: completion.acceptance.deliveryReason,
                    deliveryStatus: completion.acceptance.deliveryStatus, performance: performance, mode: intent.mode,
                    generationOutcome: completion.generationOutcome)
            case .failure(let error):
                terminalFailures[intent.id] = error
                let failure = SessionFailurePresentation(error: error)
                snapshot = SessionExecutionSnapshot(id: intent.id,
                    phase: error is CancellationError ? .cancelled : .failed, transcript: privateText ? "" : snapshot.transcript, error: failure.message,
                    performance: performance, mode: intent.mode, recoveryAction: failure.recovery)
            }
            terminalSnapshots[intent.id] = snapshot
            for (id, callback) in Array(settlementObservers) where settlementObservers[id] != nil { callback(intent, result) }
            if !privateText, case .success(let completion) = result {
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
