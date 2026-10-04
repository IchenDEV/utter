import Foundation

@MainActor
package final class StateNotifications {
    private var pending: [() -> Void] = []
    private var transactionDepth = 0
    private var isDelivering = false

    package init() {}

    package func settle<Value>(_ operation: () throws -> Value) rethrows -> Value {
        transactionDepth += 1
        defer { transactionDepth -= 1; deliver() }
        return try operation()
    }

    package func enqueue(_ notification: @escaping () -> Void) {
        pending.append(notification)
        deliver()
    }

    private func deliver() {
        guard transactionDepth == 0, !isDelivering else { return }
        isDelivering = true
        var index = 0
        while index < pending.count {
            let notification = pending[index]
            index += 1
            notification()
        }
        pending.removeAll(keepingCapacity: true)
        isDelivering = false
    }
}
