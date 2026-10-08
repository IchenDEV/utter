import Foundation

package struct PreparedModelGeneration: Sendable {
    package let storageRoot: URL
    package let candidate: URL
    package let destination: URL
    package let backup: URL?
    private let retainedBackup = ModelBackupRetention()

    var mayDiscardBackup: Bool { !retainedBackup.isRetained }
    func retainBackup() { retainedBackup.retain() }
}

private final class ModelBackupRetention: @unchecked Sendable {
    private let lock = NSLock()
    private var retained = false
    var isRetained: Bool {
        lock.lock()
        defer { lock.unlock() }
        return retained
    }
    func retain() {
        lock.lock()
        defer { lock.unlock() }
        retained = true
    }
}

package enum ModelGenerationError: LocalizedError {
    case missingSource(URL)
    case symlinkCycle(URL)
    case restorationFailed(backup: URL, cause: Error)

    package var errorDescription: String? {
        switch self {
        case .missingSource(let url):
            return "Staged model output is missing: \(url.path)"
        case .symlinkCycle(let url):
            return "Staged model contains a symbolic-link cycle: \(url.path)"
        case .restorationFailed(let backup, let cause):
            return "Model restoration failed; the previous model is retained at \(backup.path): \(cause.localizedDescription)"
        }
    }
}
