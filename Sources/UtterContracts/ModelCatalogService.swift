import Foundation

package struct ModelCatalogSnapshot: Equatable, Sendable {
    package let whisper: [CatalogModelEntry]
    package let text: [CatalogModelEntry]
    package let speech: [CatalogModelEntry]
    package init(whisper: [CatalogModelEntry], text: [CatalogModelEntry], speech: [CatalogModelEntry]) {
        self.whisper = whisper
        self.text = text
        self.speech = speech
    }
}

@MainActor
package protocol ModelCatalogService: AnyObject {
    var snapshot: ModelCatalogSnapshot { get }
    func observe(_ callback: @escaping (ModelCatalogSnapshot) -> Void) -> UUID
    func removeObserver(_ id: UUID)
    func refreshStatus(recheckingErrors: Bool)
    func downloadWhisper(_ id: String) async
    func downloadLLM(_ id: String) async
    func downloadASR(_ id: String, onProgress: ((DownloadProgressInfo) -> Void)?) async
    func cancelDownload(_ id: String, kind: ModelDownloadKind)
    func deleteWhisper(_ id: String) async
    func deleteLLM(_ id: String) async
    func deleteASR(_ id: String) async
    func addCustomLLM(_ modelID: String)
    func addLocalWhisper(_ url: URL)
    func addLocalLLM(_ url: URL)
    func updateWhisperStatus(_ id: String, status: CatalogModelStatus, detail: String)
    func updateLLMStatus(_ id: String, status: CatalogModelStatus, detail: String)
    func asrModels(for engine: SpeechEngineType) -> [CatalogModelEntry]
    func estimatedLLMDownloadBytes(_ id: String) -> Int64?
    func estimatedASRDownloadBytes(_ id: String) -> Int64?
}

package protocol TextModelDownloadService: Sendable {
    func download(_ id: String, downloadBase: URL, cacheDirectory: URL,
                  progress: @escaping @Sendable (Progress) -> Void) async throws
    func validate(_ directory: URL) async throws
}
