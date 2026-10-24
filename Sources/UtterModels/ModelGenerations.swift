import Foundation

package enum ModelGenerations {
    package static let generationDirectoryName = ".utter-generations"
    package static let cleanupDirectoryName = ".utter-cleanup"
    static let promotionDirectoryPrefix = ".utter-promotion-"
    static let backupDirectoryPrefix = ".utter-backup-"

    package static func prepare(
        source: URL, destination: URL, storageRoot: URL
    ) throws -> PreparedModelGeneration {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else {
            throw ModelGenerationError.missingSource(source)
        }

        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let candidate = parent.appendingPathComponent(
            "\(promotionDirectoryPrefix)\(UUID().uuidString)",
            isDirectory: true
        )
        var backup: URL? = nil
        do {
            var activeSymlinks = Set<String>()
            try materialize(
                from: source,
                to: candidate,
                activeSymlinks: &activeSymlinks
            )

            if fileManager.fileExists(atPath: destination.path) {
                let backupURL = parent.appendingPathComponent(
                    "\(backupDirectoryPrefix)\(UUID().uuidString)",
                    isDirectory: true
                )
                backup = backupURL
                var backupSymlinks = Set<String>()
                try materialize(
                    from: destination,
                    to: backupURL,
                    activeSymlinks: &backupSymlinks
                )
            }
            return PreparedModelGeneration(
                storageRoot: storageRoot,
                candidate: candidate,
                destination: destination,
                backup: backup
            )
        } catch {
            try? fileManager.removeItem(at: candidate)
            if let backup {
                try? fileManager.removeItem(at: backup)
            }
            throw error
        }
    }

    package static func prepareOffMainActor(
        source: URL, destination: URL, storageRoot: URL
    ) async throws -> PreparedModelGeneration {
        try await Task.detached {
            try prepare(
                source: source, destination: destination, storageRoot: storageRoot
            )
        }.value
    }

    package static func publishPreparedGeneration(
        _ prepared: PreparedModelGeneration, replacement: ((URL, URL) throws -> Void)? = nil
    ) throws {
        try publishRestoringGeneration(
            prepared,
            restoration: { try FileManager.default.moveItem(at: $0, to: $1) },
            replacement: replacement
        )
    }

    static func publishRestoringGeneration(
        _ prepared: PreparedModelGeneration,
        restoration: (URL, URL) throws -> Void,
        replacement: ((URL, URL) throws -> Void)? = nil
    ) throws {
        do {
            try (replacement ?? replaceCandidate)(prepared.candidate, prepared.destination)
        } catch {
            let publicationError = error
            guard let backup = prepared.backup else {
                try retireFailedPublication(at: prepared.destination, storageRoot: prepared.storageRoot)
                throw publicationError
            }
            prepared.retainBackup()
            let recovery = backup.deletingLastPathComponent()
                .appendingPathComponent(".utter-recovery-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.moveItem(at: backup, to: recovery)
            } catch {
                // Retain the original path if archiving itself fails. Startup
                // cleanup recognizes this marker and leaves the backup intact.
                try? Data().write(to: backup.appendingPathComponent(recoveryMarker))
                throw ModelGenerationError.restorationFailed(backup: backup, cause: error)
            }
            do {
                try retireFailedPublication(at: prepared.destination, storageRoot: prepared.storageRoot)
                try restoration(recovery, prepared.destination)
            } catch {
                throw ModelGenerationError.restorationFailed(backup: recovery, cause: error)
            }
            throw publicationError
        }
    }

    package static func discardPreparedGeneration(_ prepared: PreparedModelGeneration) {
        retireManagedDirectory(at: prepared.candidate, storageRoot: prepared.storageRoot)
        if let backup = prepared.backup, prepared.mayDiscardBackup {
            retireManagedDirectory(at: backup, storageRoot: prepared.storageRoot)
        }
    }

    package static func discardPreparedGenerationOffMainActor(
        _ prepared: PreparedModelGeneration
    ) async {
        await Task.detached {
            removeManagedDirectoryImmediately(at: prepared.candidate)
            if let backup = prepared.backup, prepared.mayDiscardBackup {
                removeManagedDirectoryImmediately(at: backup)
            }
        }.value
    }

    package static func discardPreparedGenerationsOffMainActor(
        _ prepared: [PreparedModelGeneration]
    ) async {
        await Task.detached {
            for generation in prepared {
                removeManagedDirectoryImmediately(at: generation.candidate)
                if let backup = generation.backup, generation.mayDiscardBackup {
                    removeManagedDirectoryImmediately(at: backup)
                }
            }
        }.value
    }

}
