import Foundation
import UtterMediaContracts

@MainActor
final class ScopedSpeechEvidenceService: SpeechEvidenceService {
    private let classify: (URL?) async -> Bool
    private let isCurrent: () -> Bool
    private var operations: [UUID: Task<Bool, Never>] = [:]
    private var closed = false

    init(isCurrent: @escaping () -> Bool, classify: @escaping (URL?) async -> Bool) {
        self.isCurrent = isCurrent
        self.classify = classify
    }

    func containsSpeech(at url: URL?) async throws -> Bool {
        try checkCurrent()
        let id = UUID()
        let task = Task { await classify(url) }
        operations[id] = task
        defer { operations[id] = nil }
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        try checkCurrent()
        return result
    }

    func revoke() {
        closed = true
        for task in operations.values { task.cancel() }
    }

    func close() async {
        revoke()
        let pending = Array(operations.values)
        for task in pending { _ = await task.value }
    }

    private func checkCurrent() throws {
        try Task.checkCancellation()
        guard !closed, isCurrent() else { throw CancellationError() }
    }
}
