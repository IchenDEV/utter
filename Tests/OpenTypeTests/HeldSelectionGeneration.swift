import Foundation
import UtterContracts
import UtterMediaContracts

@MainActor
final class HeldSelectionGeneration {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    let text: String
    init(_ text: String = "请您今天同步进展。 👩🏽‍💻") { self.text = text }
    func process(_ request: ProcessingRequest) async -> ProcessingResult {
        entered = true
        await withCheckedContinuation { continuation = $0 }
        return ProcessingResult(text: text)
    }
    func waitUntilEntered() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !entered, ContinuousClock.now < deadline { await Task.yield() }
        guard entered else { throw IntegrationError.operationFailed }
    }
    func release() { continuation?.resume(); continuation = nil }
}
