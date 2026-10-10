import UtterContracts
import Foundation

package final class IntegrationClientRegistry: IntegrationClientStore {
    private enum LoadResult {
        case loaded([IntegrationClient])
        case failed

        var clients: [IntegrationClient] {
            switch self {
            case let .loaded(clients):
                return clients
            case .failed:
                return []
            }
        }
    }

    private let observerLock = NSLock()
    private var observers: [UUID: () -> Void] = [:]
    private var closed = false
    private let defaults: UserDefaults
    private let key: String
    private let reportError: (String) -> Void

    package init(defaults: UserDefaults, key: String = "integrationApprovedClients", reportError: @escaping (String) -> Void) {
        self.defaults = defaults
        self.key = key
        self.reportError = reportError
    }

    package func observeAuthorization(_ callback: @escaping () -> Void) -> UUID {
        observerLock.lock()
        defer { observerLock.unlock() }
        let id = UUID()
        if !closed { observers[id] = callback }
        return id
    }
    package func removeAuthorizationObserver(_ id: UUID) {
        observerLock.lock()
        observers[id] = nil
        observerLock.unlock()
    }
    package func close() {
        observerLock.lock()
        closed = true
        observers.removeAll()
        observerLock.unlock()
    }
    private var isOpen: Bool {
        observerLock.lock()
        defer { observerLock.unlock() }
        return !closed
    }
    private func notifyAuthorization() {
        observerLock.lock()
        let ids = observers.keys.sorted { $0.uuidString < $1.uuidString }
        observerLock.unlock()
        for id in ids {
            observerLock.lock()
            let callback = observers[id]
            observerLock.unlock()
            callback?()
        }
    }

    package func approvedClients() -> [IntegrationClient] {
        load().clients.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    package func client(id: String) -> IntegrationClient? {
        load().clients.first { $0.id == id }
    }

    package func approve(_ client: IntegrationClient) {
        guard isOpen else { return }
        let result = load()
        guard case var .loaded(clients) = result else {
            return
        }

        if let index = clients.firstIndex(where: { $0.id == client.id }) {
            let existing = clients[index]
            clients[index] = IntegrationClient(
                id: client.id,
                displayName: client.displayName,
                bundleIdentifier: client.bundleIdentifier,
                teamIdentifier: client.teamIdentifier,
                codeRequirement: client.codeRequirement,
                transport: client.transport,
                capabilities: client.capabilities,
                firstApprovedAt: existing.firstApprovedAt,
                lastUsedAt: existing.lastUsedAt
            )
        } else {
            clients.append(client)
        }

        save(clients)
        notifyAuthorization()
    }

    package func revoke(clientID: String) {
        guard isOpen else { return }
        let result = load()
        guard case let .loaded(clients) = result else {
            return
        }

        save(clients.filter { $0.id != clientID })
        notifyAuthorization()
    }

    package func markUsed(clientID: String, at date: Date = Date()) {
        guard isOpen else { return }
        let result = load()
        guard case var .loaded(clients) = result else {
            return
        }
        guard let index = clients.firstIndex(where: { $0.id == clientID }) else {
            return
        }

        clients[index].lastUsedAt = date
        save(clients)
    }

    package func isAuthorized(clientID: String, capability: IntegrationClient.Capability) -> Bool {
        guard isOpen, let client = client(id: clientID) else {
            return false
        }

        return client.capabilities.contains(capability)
    }

    private func load() -> LoadResult {
        guard let data = defaults.data(forKey: key) else {
            return .loaded([])
        }

        do {
            return .loaded(try JSONDecoder.integration.decode([IntegrationClient].self, from: data))
        } catch {
            reportError("Failed to decode integration client registry: \(error.localizedDescription)")
            return .failed
        }
    }

    private func save(_ clients: [IntegrationClient]) {
        guard let data = try? JSONEncoder.integration.encode(clients) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
