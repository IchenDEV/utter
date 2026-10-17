import Foundation
import UtterContracts

package enum UpdateEvent: Equatable, Sendable {
    case checkStarted
    case foundUpdate(version: String)
    case noUpdate
    case failed(String)
    case restartPending(version: String)
    case skipped
    case cycleFinished
}

package enum UpdateStatusReducer {
    /// `unavailable` is terminal: an inert updater never reports activity.
    package static func reduce(_ status: UpdateStatus, _ event: UpdateEvent) -> UpdateStatus {
        if case .unavailable = status { return status }
        switch (status, event) {
        case (.pendingRestart, .restartPending(let version)):
            return .pendingRestart(version: version)
        case (.pendingRestart, _):
            return status
        case (.available, .checkStarted):
            return status
        case (.available, .skipped):
            return .idle
        case (_, .skipped):
            return status
        case (_, .checkStarted):
            return .checking
        case (_, .foundUpdate(let version)):
            return .available(version: version)
        case (_, .noUpdate):
            return .upToDate
        case (_, .failed(let message)):
            return .failed(message)
        case (_, .restartPending(let version)):
            return .pendingRestart(version: version)
        case (.checking, .cycleFinished):
            return .idle
        case (_, .cycleFinished):
            return status
        }
    }
}
