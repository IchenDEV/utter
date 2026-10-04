import Foundation
import UtterRuntime

package protocol ModelArtifactService: Sendable {
    var artifacts: [ModelArtifact] { get }
    func artifact(_ id: String) -> ModelArtifact?
    @MainActor func register(_ artifact: ModelArtifact, scope: PluginScope) throws
}

package enum ModelArtifactError: Error, Equatable {
    case duplicateID(String)
    case invalidRequiredFile(String)
    case closed
}

@MainActor
extension ModelArtifactService {
    package func register(_ artifacts: [ModelArtifact], scope: PluginScope) throws {
        for artifact in artifacts { try register(artifact, scope: scope) }
    }
}
