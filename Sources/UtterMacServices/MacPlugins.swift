import UtterContracts
import UtterRuntime

@MainActor
package enum MacPlugins {
    package static func correction() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "mac.correction",
            requires: [DataServices.settings.required, DataServices.dictionary.required,
                       DataServices.history.required, DataServices.correctionClassification.required,
                       IntegrationServices.diagnostics.required],
            provides: [MacServices.correction.reference]
        )) { context, _ in
            let settings = try context.require(DataServices.settings)
            let dictionary = try context.require(DataServices.dictionary)
            let history = try context.require(DataServices.history)
            let service = CorrectionCaptureService(
                enabled: { context.isReady && settings.values.enableCorrectionLearning },
                classification: try context.require(DataServices.correctionClassification),
                learn: { _ = dictionary.recordLearnedCandidate($0) },
                updateHistory: { history.updateUserFinalText(recordID: $0, text: $1) },
                log: Log(service: try context.require(IntegrationServices.diagnostics))
            )
            try context.scope.onRevoke { service.revoke() }
            try context.scope.onDispose { await service.close() }
            try context.provide(MacServices.correction, value: service)
        }
    }
}
