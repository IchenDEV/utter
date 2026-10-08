import Foundation
import UtterContracts

@MainActor
package final class CompositionStore: ConfigurationService {
    package let fileURL: URL
    package private(set) var document: CompositionDocument?
    package private(set) var mounted: EffectiveComposition?
    package private(set) var pending: EffectiveComposition?
    private let resolver: CompositionResolver
    private let shipped: CompositionDocument
    private var mountedDocument: CompositionDocument?
    private var legacy: CompositionLayer

    package init(
        fileURL: URL,
        resolver: CompositionResolver,
        shipped: CompositionDocument,
        legacy: CompositionLayer = CompositionLayer("legacy")
    ) throws {
        self.fileURL = fileURL
        self.resolver = resolver
        self.shipped = shipped
        self.legacy = legacy
        _ = try resolver.resolve(shipped, legacy: legacy)
    }

    package func load() throws -> EffectiveComposition {
        let loaded: CompositionDocument
        do {
            loaded = try JSONDecoder().decode(CompositionDocument.self, from: Data(contentsOf: fileURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            loaded = shipped
        }
        let effective = try resolver.resolve(loaded, legacy: legacy)
        document = loaded
        mountedDocument = loaded
        mounted = effective
        pending = nil
        return effective
    }

    package var restartRequired: Bool {
        guard let pending else { return false }
        return pending.mountedPluginIDs != mounted?.mountedPluginIDs
            || document?.bundles != mountedDocument?.bundles
    }

    package var sessionSnapshot: EffectiveComposition {
        get throws {
            guard let mounted else { throw CompositionStoreError.notLoaded }
            guard let pending else { return mounted }
            let updatedRows = Dictionary(uniqueKeysWithValues: pending.plugins.map { ($0.id, $0) })
            let rows = mounted.plugins.map { row in
                guard row.enabled, let updated = updatedRows[row.id], updated.enabled else { return row }
                return updated
            }
            var bindings = mounted.bindings
            for (capability, providerID) in pending.bindings {
                if let owner = resolver.owner(capability, providerID: providerID), mounted.mountedPluginIDs.contains(owner) {
                    bindings[capability] = providerID
                }
            }
            return EffectiveComposition(plugins: rows, bindings: bindings)
        }
    }

    package func save(_ proposed: CompositionDocument) throws {
        let effective = try resolver.resolve(proposed, legacy: legacy)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(proposed)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        document = proposed
        pending = effective
    }

    package func updateLegacy(_ proposed: CompositionLayer) throws {
        let effective = try resolver.resolve(document ?? shipped, legacy: proposed)
        legacy = proposed
        pending = effective
    }

    @discardableResult
    package func resetToShipped() throws -> URL? {
        var backup: URL?
        do {
            let original = try Data(contentsOf: fileURL)
            let destination = fileURL.appendingPathExtension("backup-" + UUID().uuidString)
            try original.write(to: destination, options: .withoutOverwriting)
            backup = destination
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {}
        try save(shipped)
        return backup
    }
}

package enum CompositionStoreError: Error { case notLoaded }
