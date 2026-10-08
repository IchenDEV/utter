import Foundation

package enum OperationDeadlineError: Error { case exceeded }

package func withOperationDeadline<Value: Sendable>(for duration: Duration,
    operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(for: duration)
            throw OperationDeadlineError.exceeded
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

package enum ProcessingDeadlines {
    @TaskLocal package static var factSupport: Duration = .seconds(45)
}
