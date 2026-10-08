import Foundation

extension ModelGenerations {
    static let recoveryMarker = ".utter-restore-required"

    package static func cleanupOrphanedGenerationStagingInBackground(
        storageRoot: URL,
        onEnter: (@Sendable () -> Void)? = nil,
        onExit: (@Sendable () -> Void)? = nil
    ) -> Task<Int, Never> {
        Task.detached(priority: .utility) {
            onEnter?()
            defer { onExit?() }
            return cleanupOrphanedGenerationStaging(storageRoot: storageRoot)
        }
    }

    package static func cleanupOrphanedGenerationStaging(storageRoot: URL) -> Int {
        let fileManager = FileManager.default
        var managedDirectories: [URL] = []

        if let enumerator = fileManager.enumerator(
            at: storageRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if name == generationDirectoryName {
                    managedDirectories.append(contentsOf: generationChildren(at: url))
                    enumerator.skipDescendants()
                    continue
                }
                if name == cleanupDirectoryName {
                    managedDirectories.append(contentsOf: cleanupChildren(at: url))
                    enumerator.skipDescendants()
                    continue
                }
                if name.hasPrefix(".utter-recovery-") || fileManager.fileExists(atPath: url.appendingPathComponent(recoveryMarker).path) {
                    enumerator.skipDescendants()
                    continue
                }
                if isManagedTemporaryDirectoryName(name), isDirectory(url) {
                    managedDirectories.append(url)
                    enumerator.skipDescendants()
                }
            }
        }

        var removed = 0
        for directory in managedDirectories.sorted(by: { $0.path.count > $1.path.count }) {
            guard (try? fileManager.removeItem(at: directory)) != nil else { continue }
            removed += 1
        }
        removeEmptyManagedRoot(
            storageRoot.appendingPathComponent(generationDirectoryName, isDirectory: true)
        )
        removeEmptyManagedRoot(
            storageRoot.appendingPathComponent(cleanupDirectoryName, isDirectory: true)
        )
        return removed
    }

    static func retireFailedPublication(at url: URL, storageRoot: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        let cleanup = storageRoot.appendingPathComponent(cleanupDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: cleanup, withIntermediateDirectories: true)
        let retired = cleanup.appendingPathComponent(UUID().uuidString)
        try fileManager.moveItem(at: url, to: retired)
        // Only the unique retired path can be removed asynchronously. A new
        // publication may already occupy the original destination.
        Task.detached { removeManagedDirectoryImmediately(at: retired) }
    }

    package static func retireManagedDirectory(at url: URL, storageRoot: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let cleanupRoot = storageRoot
            .appendingPathComponent(cleanupDirectoryName, isDirectory: true)
        let retired = cleanupRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: cleanupRoot, withIntermediateDirectories: true)
        if (try? fileManager.moveItem(at: url, to: retired)) == nil {
            Task.detached {
                removeManagedDirectoryImmediately(at: url)
            }
            return
        }
        Task.detached {
            removeManagedDirectoryImmediately(at: retired)
        }
    }

    static func removeManagedDirectoryImmediately(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var directory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && directory.boolValue
    }

    static func isManagedTemporaryDirectoryName(_ name: String) -> Bool {
        if name.hasPrefix(promotionDirectoryPrefix) {
            return UUID(uuidString: String(name.dropFirst(promotionDirectoryPrefix.count))) != nil
        }
        if name.hasPrefix(backupDirectoryPrefix) {
            return UUID(uuidString: String(name.dropFirst(backupDirectoryPrefix.count))) != nil
        }
        return false
    }

    static func generationChildren(at root: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        return children.filter { child in
            UUID(uuidString: child.lastPathComponent) != nil && isDirectory(child)
        }
    }

    static func cleanupChildren(at root: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        return children
    }

    static func removeEmptyManagedRoot(_ root: URL) {
        guard isDirectory(root),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: nil,
                  options: []
              ), contents.isEmpty else { return }
        try? FileManager.default.removeItem(at: root)
    }

}
