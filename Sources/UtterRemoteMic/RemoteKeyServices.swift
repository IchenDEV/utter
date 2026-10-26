import Foundation

/// One HID event service of the remote. Reads and writes only its `UserKeyMapping`.
package protocol RemoteKeyService: AnyObject {
    /// Stable for the life of this service; a reconnect creates a new service with a new id.
    var id: UInt64 { get }
    /// `[]` when no mapping is set, `nil` when the value cannot be read or understood
    /// (the caller must then not write, so an entry it cannot represent is never dropped).
    func mappings() -> [KeyMappingEntry]?
    func setMappings(_ entries: [KeyMappingEntry]) -> Bool
}

/// Source of the services that belong to the supported remote, already filtered by vendor and product.
@MainActor
package protocol RemoteKeyServiceProviding: AnyObject {
    func matchingServices() -> [any RemoteKeyService]
}
