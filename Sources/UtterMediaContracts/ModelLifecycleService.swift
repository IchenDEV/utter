import Foundation
import UtterContracts
import UtterRuntime

package struct ModelLifecycleSnapshot {
    package let loading: Bool
    package let speechReady: Bool
    package let textReady: Bool
    package let error: String?
    package init(loading: Bool = false, speechReady: Bool = false, textReady: Bool = false, error: String? = nil) {
        self.loading = loading; self.speechReady = speechReady; self.textReady = textReady; self.error = error
    }
}

@MainActor
package protocol ModelLifecycleService: AnyObject {
    var snapshot: ModelLifecycleSnapshot { get }
    func observe(_ callback: @escaping (ModelLifecycleSnapshot) -> Void) -> UUID
    func removeObserver(_ id: UUID)
    func preloadSpeech() async throws
    func preloadText() async throws
    func unloadSpeech(providerID: String?) async throws
    func unloadText() async throws
    func benchmark(_ modelID: String) async throws -> ModelBenchmarkResult
    func validateBundle(at url: URL) async throws
}

extension ModelServices {
    package static let lifecycle = ServiceKey<any ModelLifecycleService>("models.lifecycle")
}
