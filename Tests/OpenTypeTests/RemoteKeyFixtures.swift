import Foundation
@testable import UtterRemoteMic

/// In-memory HID service so plugin tests never touch the real remote.
final class RemoteKeyServiceFake: RemoteKeyService {
    let id: UInt64
    var entries: [KeyMappingEntry]
    private(set) var writes = 0

    init(id: UInt64 = 1, entries: [KeyMappingEntry] = []) {
        self.id = id
        self.entries = entries
    }

    func mappings() -> [KeyMappingEntry]? { entries }

    func setMappings(_ new: [KeyMappingEntry]) -> Bool {
        writes += 1
        entries = new
        return true
    }
}

@MainActor
final class RemoteKeyProviderFake: RemoteKeyServiceProviding {
    var services: [RemoteKeyServiceFake]

    init(_ services: [RemoteKeyServiceFake] = []) { self.services = services }

    func matchingServices() -> [any RemoteKeyService] { services }
}
