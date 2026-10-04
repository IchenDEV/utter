import Foundation
import UtterContracts
import UtterMediaContracts

@MainActor
final class RemoteSessionBinding {
    private let remote: any RemoteMicControlService
    private let settings: any SettingsService
    private let execution: any SessionExecutionService
    private let log: Log
    private var ownedID: UUID?
    private var observation: UUID?
    private var closed = false
    private var drains: [UUID: Task<Void, Never>] = [:]

    init(remote: any RemoteMicControlService, settings: any SettingsService,
         execution: any SessionExecutionService, diagnostics: any DiagnosticsService) {
        self.remote = remote; self.settings = settings; self.execution = execution
        log = Log(service: diagnostics)
    }

    func start() {
        guard !closed else { return }
        remote.setVoiceCallbacks(pressed: { [weak self] in self?.begin($0) },
            released: { [weak self] in self?.finish(cancel: false) },
            stopped: { [weak self] in self?.finish(cancel: true) })
        observation = settings.observe { [weak self] values in
            guard let self, !self.closed else { return }
            if !values.remoteMicEnabled { self.finish(cancel: true) }
            self.remote.setEnabled(values.remoteMicEnabled)
        }
        remote.setEnabled(settings.values.remoteMicEnabled)
    }

    private func begin(_ token: UInt64) {
        guard !closed, settings.values.remoteMicEnabled else { return }
        let id = UUID()
        do {
            try execution.start(SessionIntent(id: id, input: .remote(token: token)))
            ownedID = id
        } catch { log.error("Remote voice session could not start: \(error.localizedDescription)") }
    }

    private func finish(cancel: Bool) {
        guard let id = ownedID else { return }
        ownedID = nil
        if cancel { execution.cancel(id) } else { execution.requestStop(id, at: .seconds(ProcessInfo.processInfo.systemUptime)) }
        let taskID = UUID()
        drains[taskID] = Task { [weak self, execution] in
            await execution.stop(id)
            self?.drains[taskID] = nil
        }
    }

    func revoke() {
        guard !closed else { return }
        closed = true
        if let observation { settings.removeObserver(observation) }
        observation = nil
        remote.setVoiceCallbacks(pressed: nil, released: nil, stopped: nil)
        finish(cancel: true)
        remote.setEnabled(false)
    }

    func close() async {
        revoke()
        for task in Array(drains.values) { await task.value }
    }
}
