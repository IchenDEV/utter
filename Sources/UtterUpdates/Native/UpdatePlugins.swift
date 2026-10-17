import Foundation
import UtterContracts
import UtterRuntime

@MainActor
package enum UpdatePlugins {
    package static let pluginID = "updates.sparkle"

    package static func updater() -> PluginRegistration {
        updater(environment: BundleUpdateEnvironment.current()) { _, hooks in
            SparkleUpdateDriver(hooks: hooks)
        }
    }

    static func updater(environment: UpdateEnvironment, makeDriver: @escaping UpdateController.DriverFactory) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: pluginID,
            requires: [
                DataServices.settings.required, IntegrationServices.diagnostics.required,
                SessionServices.execution.required, ModelServices.catalog.required,
            ],
            provides: [UpdateServices.updater.reference]
        )) { context, _ in
            let settings = try context.require(DataServices.settings)
            let execution = try context.require(SessionServices.execution)
            let catalog = try context.require(ModelServices.catalog)
            let log = Log(service: try context.require(IntegrationServices.diagnostics))
            let controller = UpdateController(
                resolution: UpdateConfiguration.resolve(environment), log: { log.info($0) }, makeDriver: makeDriver)

            controller.setSessionBusy(execution.snapshot.isBusy)
            controller.setModelBusy(UpdateBusySignals.isModelBusy(catalog.snapshot))
            let observations = (
                settings: settings.observe { controller.setAutomaticChecks($0.automaticUpdateChecks) },
                session: execution.observe { controller.setSessionBusy($0.isBusy) },
                catalog: catalog.observe { controller.setModelBusy(UpdateBusySignals.isModelBusy($0)) }
            )
            try context.scope.onRevoke { controller.stop() }
            try context.scope.onDispose {
                settings.removeObserver(observations.settings)
                execution.removeObserver(observations.session)
                catalog.removeObserver(observations.catalog)
                controller.stop()
            }
            try context.scope.onReady { controller.start(automaticChecks: settings.values.automaticUpdateChecks) }
            try context.provide(UpdateServices.updater, value: controller)
        }
    }
}
