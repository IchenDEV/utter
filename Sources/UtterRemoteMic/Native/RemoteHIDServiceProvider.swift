import Foundation
import IOKit
import IOKit.hidsystem

/// A HID event service obtained from the system event client. It keeps the client that
/// created it alive: releasing the client while a service is in use crashes the process.
final class RemoteHIDService: RemoteKeyService {
    private static let mappingKey = "UserKeyMapping" as CFString

    let id: UInt64
    private let client: IOHIDEventSystemClient
    private let service: IOHIDServiceClient

    init(id: UInt64, client: IOHIDEventSystemClient, service: IOHIDServiceClient) {
        self.id = id
        self.client = client
        self.service = service
    }

    func mappings() -> [KeyMappingEntry]? {
        RemoteKeyMappingCodec.decode(IOHIDServiceClientCopyProperty(service, Self.mappingKey))
    }

    func setMappings(_ entries: [KeyMappingEntry]) -> Bool {
        IOHIDServiceClientSetProperty(service, Self.mappingKey, RemoteKeyMappingCodec.encode(entries) as NSArray)
    }
}

/// Finds the supported remote's HID services through the public event system client.
/// A fresh client is created per poll and retained by the services it yields, so a
/// reconnected remote's new service is always visible.
@MainActor
final class RemoteHIDServiceProvider: RemoteKeyServiceProviding {
    private var catalog = RemoteKeyServiceCatalog()

    func matchingServices() -> [any RemoteKeyService] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        // Every service object, including the temporary list, must be released before the client.
        return withExtendedLifetime(client) {
            guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
                return [any RemoteKeyService]()
            }
            let selected = catalog.select(
                from: services,
                id: { (IOHIDServiceClientGetRegistryID($0) as? NSNumber)?.uint64Value },
                identity: { service in
                    (Self.integer(service, "VendorID"), Self.integer(service, "ProductID"))
                }
            )
            return selected.compactMap { service -> (any RemoteKeyService)? in
                guard let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value else { return nil }
                return RemoteHIDService(id: id, client: client, service: service)
            }
        }
    }

    private static func integer(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue
    }
}
