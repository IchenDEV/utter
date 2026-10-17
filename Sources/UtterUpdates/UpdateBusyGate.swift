import Foundation

/// Holds a requested relaunch while Utter is dictating or working on a model, then releases it once.
@MainActor
package final class UpdateBusyGate {
    private var sessionBusy = false
    private var modelBusy = false
    private var pending: (() -> Void)?
    private var revoked = false

    package init() {}

    package var isBusy: Bool { sessionBusy || modelBusy }

    /// Returns `true` when the relaunch is held. A held handler runs exactly once, when both
    /// signals clear. A second request while one is held replaces it.
    package func postpone(_ proceed: @escaping () -> Void) -> Bool {
        guard !revoked, isBusy else { return false }
        pending = proceed
        return true
    }

    package func setSessionBusy(_ busy: Bool) {
        sessionBusy = busy
        releaseIfIdle()
    }

    package func setModelBusy(_ busy: Bool) {
        modelBusy = busy
        releaseIfIdle()
    }

    /// Drops any held relaunch without running it. Shutdown owns the process from here.
    package func revoke() {
        revoked = true
        pending = nil
    }

    private func releaseIfIdle() {
        guard !revoked, !isBusy, let proceed = pending else { return }
        pending = nil
        proceed()
    }
}
