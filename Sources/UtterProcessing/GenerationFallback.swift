import Foundation
import UtterContracts

package enum GenerationFallback {
    package static func run<Value>(
        fallbackEnabled: Bool = true,
        espresso: () async throws -> Value,
        prepareForMLXFallback: () async -> Void = {},
        mlx: () async throws -> Value
    ) async throws -> (value: Value, usedMLX: Bool) {
        try Task.checkCancellation()
        do {
            let value = try await espresso()
            try Task.checkCancellation()
            return (value, false)
        } catch {
            try Task.checkCancellation()
            guard fallbackEnabled else { throw error }
            let espressoFailure = error.localizedDescription
            await prepareForMLXFallback()
            try Task.checkCancellation()
            do {
                let value = try await mlx()
                try Task.checkCancellation()
                return (value, true)
            } catch {
                try Task.checkCancellation()
                throw EspressoMLXFallbackError(
                    espressoFailure: espressoFailure,
                    mlxFailure: error.localizedDescription
                )
            }
        }
    }

}
