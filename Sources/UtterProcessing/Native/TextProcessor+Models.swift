import UtterContracts
import Foundation

extension TextProcessor {
    package func withLocalModelAccess<Value>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        try await localModelAccessGate.withAccess(operation)
    }

    package static func withEspressoOutcomeTracking<Value>(
        _ operation: () async throws -> Value
    ) async rethrows -> Value {
        if espressoGenerationTracker != nil {
            return try await operation()
        }
        return try await $espressoGenerationTracker.withValue(EspressoGenerationTracker()) {
            try await operation()
        }
    }

    package static func recordEspressoOutcome(_ outcome: EspressoGenerationOutcome) async {
        await espressoGenerationTracker?.record(outcome)
    }

    package static func clearEspressoOutcome() async {
        await espressoGenerationTracker?.clear()
    }

    package func consumeEspressoOutcome() async -> EspressoGenerationOutcome? {
        await Self.espressoGenerationTracker?.consume()
    }

    package func resetModels() async throws {
        try await withLocalModelAccess {
            for descriptor in await self.providers.descriptors {
                try await self.providers.reset(id: descriptor.id)
            }
            if let images = self.imageProviders {
                for descriptor in await images.descriptors { try await images.reset(id: descriptor.id) }
            }
        }
    }
}
