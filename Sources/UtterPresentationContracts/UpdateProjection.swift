import Foundation
import Combine
import UtterContracts

@MainActor
package final class UpdateProjection: ObservableObject {
    private let service: any UpdateService
    private var observation: UUID?
    @Published package private(set) var status: UpdateStatus

    package init(service: any UpdateService) {
        self.service = service
        status = service.status
        observation = service.observe { [weak self] in self?.status = $0 }
    }

    package func checkForUpdates() { service.checkForUpdates() }

    package func dispose() {
        if let observation { service.removeObserver(observation) }
        observation = nil
    }
}

package enum UpdatePresentation {
    package static func menuTitle(_ status: UpdateStatus) -> String {
        switch status {
        case .available(let version): return String(format: L("update.menu.available"), version)
        case .pendingRestart: return L("update.menu.pending")
        case .checking: return L("update.status.checking")
        case .unavailable, .idle, .upToDate, .failed: return L("update.check")
        }
    }

    package static func statusLine(_ status: UpdateStatus) -> String? {
        switch status {
        case .unavailable, .idle: return nil
        case .checking: return L("update.status.checking")
        case .upToDate: return L("update.status.up_to_date")
        case .available(let version): return String(format: L("update.status.available"), version)
        case .pendingRestart(let version): return String(format: L("update.status.pending"), version)
        case .failed: return L("update.status.failed")
        }
    }

    package static func canCheck(_ status: UpdateStatus) -> Bool {
        switch status {
        case .idle, .upToDate, .available, .failed: return true
        case .unavailable, .checking, .pendingRestart: return false
        }
    }

    package static func isHighlighted(_ status: UpdateStatus) -> Bool {
        switch status {
        case .available, .pendingRestart: return true
        default: return false
        }
    }
}
