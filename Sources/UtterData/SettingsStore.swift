import Foundation
import UtterContracts

package final class SettingsStore: SettingsService {
    let defaults: UserDefaults
    private let lock = NSRecursiveLock()
    private var current: SettingsValues
    private var observers: [UUID: (SettingsValues) -> Void] = [:]
    private var pending: [(SettingsValues, [UUID])] = []
    private var isNotifying = false

    package var values: SettingsValues {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    package init(defaults: UserDefaults) {
        self.defaults = defaults
        current = Self.load(defaults: defaults)
    }

    package func update(_ mutation: (inout SettingsValues) -> Void) {
        lock.lock()
        var updated = current
        mutation(&updated)
        guard updated != current else { lock.unlock(); return }
        current = updated
        persist(updated)
        Loc.use(updated.uiLanguage)
        pending.append((updated, observers.keys.sorted { $0.uuidString < $1.uuidString }))
        guard !isNotifying else { lock.unlock(); return }
        isNotifying = true
        lock.unlock()
        notifyObservers()
    }

    package func observe(_ callback: @escaping (SettingsValues) -> Void) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        observers[id] = callback
        return id
    }

    package func removeObserver(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        observers[id] = nil
    }

    package func resetDeveloperHTTPToken() {
        let token = Self.generateDeveloperHTTPToken()
        update { $0.developerHTTPToken = token }
    }

    private func notifyObservers() {
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                isNotifying = false
                lock.unlock()
                return
            }
            let (snapshot, ids) = pending.removeFirst()
            lock.unlock()
            for id in ids {
                lock.lock()
                let callback = observers[id]
                lock.unlock()
                callback?(snapshot)
            }
        }
    }
}
