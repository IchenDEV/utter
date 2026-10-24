import Foundation
@testable import UtterRemoteMic

final class FakeKeyService: RemoteKeyService {
    let id: UInt64
    var entries: [KeyMappingEntry]?
    var failSets = 0
    var ignoreWrites = false
    private(set) var writes: [[KeyMappingEntry]] = []

    init(id: UInt64, entries: [KeyMappingEntry]? = []) {
        self.id = id
        self.entries = entries
    }

    func mappings() -> [KeyMappingEntry]? { entries }

    func setMappings(_ new: [KeyMappingEntry]) -> Bool {
        writes.append(new)
        if failSets > 0 {
            failSets -= 1
            return false
        }
        if !ignoreWrites { entries = new }
        return true
    }
}

@MainActor
final class FakeKeyProvider: RemoteKeyServiceProviding {
    var services: [FakeKeyService] = []
    private(set) var queries = 0

    func matchingServices() -> [any RemoteKeyService] {
        queries += 1
        return services
    }
}

final class FakeClock {
    var time: TimeInterval = 100
    func advance(_ seconds: TimeInterval) { time += seconds }
}
