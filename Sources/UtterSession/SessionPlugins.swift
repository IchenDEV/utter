import UtterContracts
import UtterRuntime

@MainActor
package enum SessionPlugins {
    package static func outputs() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "session.outputs", requires: [DataServices.notifications.required],
            provides: [SessionServices.outputs.reference])) { context, _ in
            let state = SessionOutputState(notifications: try context.require(DataServices.notifications))
            try context.scope.onRevoke { state.close() }
            try context.provide(SessionServices.outputs, value: state)
        }
    }

    package static func execution() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "session.execution",
            requires: [SessionServices.workflows.required, DataServices.history.required, DataServices.notifications.required],
            provides: [SessionServices.execution.reference]
        )) { context, _ in
            let driver = SessionDriver(workflows: try context.require(SessionServices.workflows),
                                       history: try context.require(DataServices.history),
                                       notifications: try context.require(DataServices.notifications), isReady: { context.isReady })
            try context.scope.onRevoke { driver.revoke() }
            try context.scope.onDispose { await driver.close() }
            try context.provide(SessionServices.execution, value: driver)
        }
    }

    package static func api() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "session.api",
            requires: [DataServices.settings.required, DataServices.credentials.required,
                       DataServices.notifications.required, IntegrationServices.clients.required, SessionServices.execution.optional],
            provides: [SessionServices.api.reference]
        )) { context, _ in
            let execution = try context.optional(SessionServices.execution)
            let settings = try context.require(DataServices.settings)
            let credentials = try context.require(DataServices.credentials)
            let service = OpenTypeService(
                settingsProvider: {
                    IntegrationServiceSettings(developerInterfaceEnabled: settings.values.developerInterfaceEnabled,
                                               httpToken: credentials.snapshot.developerHTTPToken)
                }, registry: try context.require(IntegrationServices.clients),
                notifications: try context.require(DataServices.notifications),
                execution: execution
            )
            if let execution {
                let progress = execution.observeProgress { service.projectExecution($0, snapshot: $1) }
                try context.scope.onDispose { execution.removeProgressObserver(progress) }
                let observation = execution.observeSettlement { service.settleExecution($0, result: $1) }
                try context.scope.onDispose { execution.removeSettlementObserver(observation) }
            }
            try context.scope.onDispose { service.close() }
            try context.provide(SessionServices.api, value: service)
        }
    }
}
