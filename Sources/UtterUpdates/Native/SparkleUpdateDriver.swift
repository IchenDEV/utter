import Foundation
import Sparkle

/// Owns the Sparkle updater. Scheduled updates are never shown by Sparkle itself: they surface
/// through `UpdateService.status`, and a user-initiated check shows Sparkle's standard window.
@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriver {
    private let hooks: UpdateDriverHooks
    private let hostBundle: Bundle
    private var updater: SPUUpdater?
    private var userDriver: SPUStandardUserDriver?
    private var stopped = false

    init(hooks: UpdateDriverHooks, hostBundle: Bundle = .main) {
        self.hooks = hooks
        self.hostBundle = hostBundle
    }

    func start(automaticChecks: Bool) throws {
        let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: self)
        let updater = SPUUpdater(
            hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: userDriver, delegate: self)
        updater.automaticallyChecksForUpdates = automaticChecks
        updater.automaticallyDownloadsUpdates = false
        try updater.start()
        self.userDriver = userDriver
        self.updater = updater
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    /// Sparkle has no public stop. Releasing the updater ends its schedule, and `stopped` makes
    /// any callback already in flight inert.
    func stop() {
        stopped = true
        updater = nil
        userDriver = nil
    }
}

extension SparkleUpdateDriver: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard !stopped else { return }
        hooks.emit(.foundUpdate(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        guard !stopped else { return }
        hooks.emit(.noUpdate)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        guard !stopped else { return }
        if Self.isBenignAbort(error) { return }
        hooks.emit(.failed(error.localizedDescription))
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard !stopped else { return }
        hooks.emit(.cycleFinished)
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        guard !stopped, choice == .skip else { return }
        hooks.emit(.skipped)
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !stopped else { return false }
        return hooks.postponeRelaunch(item.displayVersionString, installHandler)
    }

    /// Sparkle reports "no update" and a declined authorization through the abort callback.
    private static func isBenignAbort(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return false }
        let benign: [SUError] = [.noUpdateError, .installationCanceledError, .installationAuthorizeLaterError]
        return benign.contains { $0.rawValue == nsError.code }
    }
}

extension SparkleUpdateDriver: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool { false }
}
