import Foundation

package enum AppleSpeechTranscriptionFallback {
    package static func run(analyzer: () async throws -> String, legacy: () async throws -> String,
                            reportFailure: (Error) -> Void) async throws -> String {
        try Task.checkCancellation()
        do {
            let text = try await analyzer()
            try Task.checkCancellation()
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            reportFailure(error)
        }
        try Task.checkCancellation()
        let text = try await legacy()
        try Task.checkCancellation()
        return text
    }
}
