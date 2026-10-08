import UtterRuntime
import UtterPresentationContracts

@MainActor
final class PresentationRegistry: PresentationCatalog {
    private let registry = ContributionRegistry<PresentationContribution>()
    func contributions(for role: PresentationRole) -> [PresentationContribution] {
        registry.ids.compactMap { registry.value(for: $0) }.filter { $0.role == role }
            .sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }
    func register(_ contribution: PresentationContribution, scope: PluginScope) throws {
        try registry.contribute(contribution.id, value: contribution, scope: scope)
    }
}
