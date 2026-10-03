import Foundation
import UtterMediaContracts

final class CaptureCallbackGate: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var active = true

    func revoke() {
        lock.lock()
        defer { lock.unlock() }
        active = false
    }

    func guarding(_ callbacks: CaptureCallbacks) -> CaptureCallbacks {
        CaptureCallbacks(
            level: { [self] value in perform { callbacks.level(value) } },
            buffer: callbacks.buffer.map { callback in { [self] buffer in perform { callback(buffer) } } },
            switchedInput: { [self] in perform(callbacks.switchedInput) },
            inputUnavailable: { [self] in perform(callbacks.inputUnavailable) }
        )
    }

    private func perform(_ callback: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        callback()
    }
}
