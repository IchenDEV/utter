import Foundation
import UtterContracts

/// The seam between portable update policy and the native updater framework.
@MainActor
package protocol UpdateDriver: AnyObject {
    func start(automaticChecks: Bool) throws
    func setAutomaticChecks(_ enabled: Bool)
    func checkForUpdates()
    func stop()
}

package struct UpdateDriverHooks {
    package let emit: @MainActor (UpdateEvent) -> Void
    /// Returns `true` when the relaunch is held and `proceed` will run later.
    package let postponeRelaunch: @MainActor (_ version: String, _ proceed: @escaping () -> Void) -> Bool

    package init(emit: @escaping @MainActor (UpdateEvent) -> Void,
                 postponeRelaunch: @escaping @MainActor (_ version: String, _ proceed: @escaping () -> Void) -> Bool) {
        self.emit = emit
        self.postponeRelaunch = postponeRelaunch
    }
}

@MainActor
package final class UpdateController: UpdateService {
    package typealias DriverFactory = @MainActor (UpdateConfiguration, UpdateDriverHooks) -> any UpdateDriver

    package private(set) var status: UpdateStatus
    private let configuration: UpdateConfiguration?
    private let makeDriver: DriverFactory
    private let log: @MainActor (String) -> Void
    private let gate = UpdateBusyGate()
    private var driver: (any UpdateDriver)?
    private var observers: [UUID: @MainActor (UpdateStatus) -> Void] = [:]
    private var stopped = false

    package init(resolution: UpdateConfiguration.Resolution,
                 log: @escaping @MainActor (String) -> Void = { _ in },
                 makeDriver: @escaping DriverFactory) {
        switch resolution {
        case .enabled(let configuration):
            self.configuration = configuration
            status = .idle
        case .unavailable(let reason):
            configuration = nil
            status = .unavailable(reason)
        }
        self.log = log
        self.makeDriver = makeDriver
    }

    package func start(automaticChecks: Bool) {
        guard let configuration, driver == nil, !stopped else { return }
        let hooks = UpdateDriverHooks(
            emit: { [weak self] event in self?.apply(event) },
            postponeRelaunch: { [weak self] version, proceed in
                guard let self, self.gate.postpone(proceed) else { return false }
                self.apply(.restartPending(version: version))
                return true
            })
        let driver = makeDriver(configuration, hooks)
        do {
            try driver.start(automaticChecks: automaticChecks)
            self.driver = driver
        } catch {
            log("Updater failed to start: \(error.localizedDescription)")
            driver.stop()
            publish(.unavailable(.startFailed))
        }
    }

    package func setAutomaticChecks(_ enabled: Bool) {
        driver?.setAutomaticChecks(enabled)
    }

    package func setSessionBusy(_ busy: Bool) { gate.setSessionBusy(busy) }

    package func setModelBusy(_ busy: Bool) { gate.setModelBusy(busy) }

    package func checkForUpdates() {
        guard let driver else { return }
        apply(.checkStarted)
        driver.checkForUpdates()
    }

    /// Shutdown owns the process from here: a held relaunch is dropped and no event is applied.
    package func stop() {
        stopped = true
        gate.revoke()
        driver?.stop()
        driver = nil
    }

    package func observe(_ callback: @escaping @MainActor (UpdateStatus) -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    package func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    private func apply(_ event: UpdateEvent) {
        guard !stopped else { return }
        if case .failed(let message) = event { log("Update check failed: \(message)") }
        let next = UpdateStatusReducer.reduce(status, event)
        guard next != status else { return }
        publish(next)
    }

    private func publish(_ next: UpdateStatus) {
        status = next
        for callback in observers.values { callback(next) }
    }
}
