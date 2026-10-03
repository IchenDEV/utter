import UtterContracts
import Foundation

final class IntegrationClientRegistry {
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

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "integrationApprovedClients") {
        self.defaults = defaults
        self.key = key
    }

    func approvedClients() -> [IntegrationClient] {
        load().clients.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func client(id: String) -> IntegrationClient? {
        load().clients.first { $0.id == id }
    }

    func approve(_ client: IntegrationClient) {
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
    }

    func revoke(clientID: String) {
        let result = load()
        guard case let .loaded(clients) = result else {
            return
        }

        save(clients.filter { $0.id != clientID })
    }

    func markUsed(clientID: String, at date: Date = Date()) {
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

    func isAuthorized(clientID: String, capability: IntegrationClient.Capability) -> Bool {
        guard let client = client(id: clientID) else {
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
            Log.error("Failed to decode integration client registry: \(error.localizedDescription)")
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
