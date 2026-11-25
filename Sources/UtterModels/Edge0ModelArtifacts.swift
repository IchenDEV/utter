import UtterContracts
import UtterRuntime

package enum Edge0ModelArtifacts {
    package static var models: [ModelArtifact] {
        [
            ModelArtifact(
                id: Edge0Model.defaultID,
                kind: .llm,
                displayName: "Edge0 8B-A1B",
                hint: L("model.edge0_8b"),
                family: .edge0,
                tier: .standard,
                requiredFiles: Edge0Model.requiredFiles,
                rank: 100,
                memoryRequirements: ModelMemoryRequirements(minimumGB: 6, recommendedGB: 8),
                revision: Edge0Model.revision,
                downloadsOnlyRequiredFiles: true,
                runtime: .edge0,
                repositoryHost: .modelScope
            )
        ]
    }
}

@MainActor
package enum Edge0Plugins {
    package static func models() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "models.edge0",
            requires: [ModelServices.artifacts.required]
        )) { context, _ in
            try context.require(ModelServices.artifacts).register(Edge0ModelArtifacts.models, scope: context.scope)
        }
    }
}
