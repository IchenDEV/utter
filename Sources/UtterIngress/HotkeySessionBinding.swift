import Foundation
import UtterContracts

@MainActor
package final class HotkeySessionBinding {
    private let hotkeys: any HotkeyControlService
    private let execution: any SessionExecutionService
    private let settings: any SettingsService
    private let log: Log
    private var closed = false
    private var ownedID: UUID?
    private var tasks: [UUID: Task<Void, Never>] = [:]

    package init(hotkeys: any HotkeyControlService, execution: any SessionExecutionService,
                 settings: any SettingsService, diagnostics: any DiagnosticsService) {
        self.hotkeys = hotkeys; self.execution = execution; self.settings = settings
        log = Log(service: diagnostics)
    }

    package func start() {
        guard !closed else { return }
        hotkeys.setCallbacks(start: { [weak self] in self?.begin($0) },
            stop: { [weak self] _ in self?.stop() },
            promote: { [weak self] in self?.promote($0) ?? false },
            cancel: { [weak self] in self?.cancel() })
        hotkeys.setEnabled(true)
    }

    private func begin(_ action: HotkeyAction) {
        guard !closed, let id = hotkeys.captureID else { return }
        let mode: TextProcessingMode? = action == .translation ? .translation(settings.values.translationTargetLanguage) : nil
        do {
            try execution.start(SessionIntent(id: id, input: .local, mode: mode))
            ownedID = id
        } catch { log.error("Hotkey session could not start: \(error.localizedDescription)") }
    }

    private func promote(_ reason: HotkeyPromotion) -> Bool {
        guard !closed, let id = hotkeys.captureID, id == ownedID else { return false }
        return execution.promoteToTranslation(id, reason: reason)
    }

    private func stop() {
        guard !closed, let id = hotkeys.captureID, id == ownedID else { return }
        let timestamp = hotkeys.eventTimestamp
        execution.requestStop(id, at: timestamp)
        drain(id)
    }

    private func cancel() {
        guard !closed, let id = hotkeys.captureID, id == ownedID else { return }
        execution.cancel(id)
        drain(id)
    }

    private func drain(_ id: UUID) {
        let key = UUID()
        tasks[key] = Task { [weak self, execution] in
            await execution.stop(id)
            if self?.ownedID == id { self?.ownedID = nil }
            self?.tasks[key] = nil
        }
    }

    package func revoke() {
        guard !closed else { return }
        closed = true
        hotkeys.setCallbacks(start: nil, stop: nil, promote: nil, cancel: nil)
        hotkeys.setEnabled(false)
        if let id = ownedID { execution.cancel(id); drain(id) }
    }

    package func close() async {
        revoke()
        for task in Array(tasks.values) { await task.value }
    }
}
