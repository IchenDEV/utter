import Foundation
import UtterRuntime

package enum UpdateUnavailableReason: Equatable, Sendable {
    case notApplicationBundle
    case missingFeed
    case insecureFeed
    case invalidPublicKey
    case adHocSigned
    case startFailed
}

package enum UpdateStatus: Equatable, Sendable {
    case unavailable(UpdateUnavailableReason)
    case idle
    case checking
    case upToDate
    case available(version: String)
    case pendingRestart(version: String)
    case failed(String)

    package var isAvailable: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

@MainActor
package protocol UpdateService: AnyObject {
    var status: UpdateStatus { get }
    func observe(_ callback: @escaping @MainActor (UpdateStatus) -> Void) -> UUID
    func removeObserver(_ id: UUID)
    func checkForUpdates()
}

package enum UpdateServices {
    package static let updater = ServiceKey<any UpdateService>("updates.updater")
}
