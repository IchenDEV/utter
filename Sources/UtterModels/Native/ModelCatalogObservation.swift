import Foundation
import UtterContracts

extension ModelCatalog {
    package var snapshot: ModelCatalogSnapshot {
        ModelCatalogSnapshot(whisper: whisperModels, text: llmModels, speech: asrModels)
    }
    package func observe(_ callback: @escaping (ModelCatalogSnapshot) -> Void) -> UUID {
        let id = UUID()
        if !closed { observers[id] = callback }
        return id
    }
    package func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    func notifyObservers() {
        guard !closed else { return }
        let value = snapshot
        for (id, callback) in Array(observers) where observers[id] != nil { callback(value) }
    }
}
