import Foundation
import Combine
import UtterContracts

@MainActor
package final class ModelCatalogProjection: ObservableObject {
    package typealias ModelEntry = CatalogModelEntry
    package typealias ModelFamily = CatalogModelFamily
    package typealias ModelStatus = CatalogModelStatus
    private let service: any ModelCatalogService
    private var observation: UUID?
    @Published private var snapshot: ModelCatalogSnapshot
    @Published private var benchmarking: Set<String> = []
    @Published private var benchmarks: [String: ModelBenchmarkResult] = [:]

    package init(service: any ModelCatalogService) {
        self.service = service
        snapshot = service.snapshot
        observation = service.observe { [weak self] in self?.snapshot = $0 }
    }
    package var whisperModels: [ModelEntry] { snapshot.whisper }
    package var asrModels: [ModelEntry] { snapshot.speech }
    package var llmModels: [ModelEntry] {
        snapshot.text.map { entry in
            var entry = entry
            entry.isBenchmarking = benchmarking.contains(entry.id)
            entry.benchmarkTPS = benchmarks[entry.id]?.tokensPerSecond
            return entry
        }
    }
    package func setBenchmarking(_ id: String, result: ModelBenchmarkResult? = nil, active: Bool) {
        if active { benchmarking.insert(id); benchmarks[id] = nil }
        else { benchmarking.remove(id); if let result { benchmarks[id] = result } }
    }
    package func benchmark(_ id: String) -> ModelBenchmarkResult? { benchmarks[id] }
    package func asrModels(for engine: SpeechEngineType) -> [ModelEntry] { service.asrModels(for: engine) }
    package func estimatedLLMDownloadBytes(_ id: String) -> Int64? { service.estimatedLLMDownloadBytes(id) }
    package func estimatedASRDownloadBytes(_ id: String) -> Int64? { service.estimatedASRDownloadBytes(id) }
    package func refreshStatus(recheckingErrors: Bool) { service.refreshStatus(recheckingErrors: recheckingErrors) }
    package func downloadWhisper(_ id: String) async { await service.downloadWhisper(id) }
    package func downloadLLM(_ id: String) async { await service.downloadLLM(id) }
    package func downloadASR(_ id: String) async { await service.downloadASR(id, onProgress: nil) }
    package func cancelDownload(_ id: String, kind: ModelDownloadKind) { service.cancelDownload(id, kind: kind) }
    package func deleteWhisper(_ id: String) async { await service.deleteWhisper(id) }
    package func deleteLLM(_ id: String) async { await service.deleteLLM(id) }
    package func deleteASR(_ id: String) async { await service.deleteASR(id) }
    package func addCustomLLM(_ id: String) { service.addCustomLLM(id) }
    package func addLocalWhisper(_ url: URL) { service.addLocalWhisper(url) }
    package func addLocalLLM(_ url: URL) { service.addLocalLLM(url) }
    package func dispose() {
        if let observation { service.removeObserver(observation) }
        observation = nil
    }
    package static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
