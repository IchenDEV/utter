import Foundation
import Combine
import UtterContracts
import UtterMediaContracts

@MainActor
package final class ModelLifecycleProjection: ObservableObject {
    private let service: any ModelLifecycleService
    private var observation: UUID?
    @Published package private(set) var snapshot: ModelLifecycleSnapshot
    package init(service: any ModelLifecycleService) {
        self.service = service; snapshot = service.snapshot
        observation = service.observe { [weak self] in self?.snapshot = $0 }
    }
    package func preloadText() async throws { try await service.preloadText() }
    package func unloadText() async throws { try await service.unloadText() }
    package func unloadSpeech(_ id: String?) async throws { try await service.unloadSpeech(providerID: id) }
    package func benchmark(_ id: String) async throws -> ModelBenchmarkResult { try await service.benchmark(id) }
    package func validateBundle(at url: URL) async throws { try await service.validateBundle(at: url) }
    package func dispose() {
        if let observation { service.removeObserver(observation) }
        observation = nil
    }
}
