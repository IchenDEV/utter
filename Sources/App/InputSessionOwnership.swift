import Foundation

/// All input entries share this reservation, including preparation and cancellation drain.
@MainActor
final class InputSessionOwnership {
    private var current: UUID?
    private var cancelled = false

    var isBusy: Bool { current != nil }

    func acquire() throws -> UUID {
        guard current == nil else { throw IntegrationError.busy }
        let id = UUID()
        current = id
        cancelled = false
        return id
    }

    func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard current == id, !cancelled else { throw CancellationError() }
    }

    func cancel(_ id: UUID) {
        guard current == id else { return }
        cancelled = true
    }

    /// Called only after the owner has stopped touching execution resources.
    func release(_ id: UUID) {
        guard current == id else { return }
        current = nil
        cancelled = false
    }
}
