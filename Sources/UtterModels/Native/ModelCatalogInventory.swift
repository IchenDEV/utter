import UtterContracts

extension ModelCatalog {
    package func loadArtifacts(_ artifacts: [ModelArtifact]) {
        guard !closed else { return }
        artifactsByID = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.id, $0) })
        llmModels = artifacts.filter { $0.kind == .llm }.map {
            var entry = ModelEntry(id: $0.id, displayName: $0.displayName, hint: $0.hint, family: $0.family,
                tier: DeviceCapability.tier(for: $0))
            entry.runtime = $0.runtime
            entry.repositoryHost = $0.repositoryHost
            return entry
        }
        appendLocalLLMModels()
        asrModels = artifacts.filter { $0.kind == .asr }.map {
            ModelEntry(id: $0.id, displayName: $0.displayName, hint: $0.hint, family: $0.family, tier: $0.tier)
        }
        refreshStatus()
    }
}
