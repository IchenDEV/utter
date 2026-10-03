import UtterContracts
import Foundation

/// All input entries share this reservation, including preparation and cancellation drain.
@MainActor
package final class InputSessionOwnership {
    private var current: UUID?
    private var cancelled = false

    package init() {}

    package var isBusy: Bool { current != nil }

    package func acquire() throws -> UUID {
        guard current == nil else { throw IntegrationError.busy }
        let id = UUID()
        current = id
        cancelled = false
        return id
    }

    package func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard current == id, !cancelled else { throw CancellationError() }
    }

    package func cancel(_ id: UUID) {
        guard current == id else { return }
        cancelled = true
    }

    /// Called only after the owner has stopped touching execution resources.
    package func release(_ id: UUID) {
        guard current == id else { return }
        current = nil
        cancelled = false
    }
}
