import Foundation

@MainActor
package final class StateNotifications {
    private var pending: [() -> Void] = []
    private var transactionDepth = 0
    private var isDelivering = false

    package init() {}

    package func settle(_ operation: () -> Void) {
        transactionDepth += 1
        operation()
        transactionDepth -= 1
        deliver()
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
