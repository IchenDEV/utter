import Foundation

package enum PermissionRequest {
    package static func wait(start: (@escaping @Sendable (Bool) -> Void) -> Void) async throws -> Bool {
        try Task.checkCancellation()
        let response = PermissionResponse()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if response.install(continuation) { start { response.finish(.success($0)) } }
            }
        } onCancel: { response.finish(.failure(CancellationError())) }
    }
}

private final class PermissionResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Bool, Error>?
    private var continuation: CheckedContinuation<Bool, Error>?

    func install(_ continuation: CheckedContinuation<Bool, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func finish(_ result: Result<Bool, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
