import Foundation
import UtterContracts
import UtterRuntime

package struct SessionMetricsEvent: Codable {
    package let sessionID: UUID
    package let performance: SessionPerformance
    package init?(_ snapshot: SessionExecutionSnapshot) {
        guard !snapshot.isBusy, let id = snapshot.id, let performance = snapshot.performance else { return nil }
        sessionID = id
        self.performance = performance
    }
}

@MainActor
extension SessionPlugins {
    package static func metrics() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "session.metrics", requires: [
            SessionServices.execution.required, IntegrationServices.diagnostics.required
        ])) { context, _ in
            let execution = try context.require(SessionServices.execution)
            let diagnostics = try context.require(IntegrationServices.diagnostics)
            var lastID: UUID?
            let observation = execution.observe { snapshot in
                guard context.isCurrent, let event = SessionMetricsEvent(snapshot), event.sessionID != lastID else { return }
                lastID = event.sessionID
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                guard let data = try? encoder.encode(event) else { return }
                diagnostics.info("utter.session.performance " + String(decoding: data, as: UTF8.self))
            }
            try context.scope.onRevoke { execution.removeObserver(observation) }
        }
    }
}
