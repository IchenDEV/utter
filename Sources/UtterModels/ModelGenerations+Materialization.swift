import Foundation

extension ModelGenerations {

    static func materialize(
        from source: URL,
        to destination: URL,
        activeSymlinks: inout Set<String>
    ) throws {
        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        if let type = attributes[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            guard activeSymlinks.insert(source.path).inserted else {
                throw ModelGenerationError.symlinkCycle(source)
            }
            defer { activeSymlinks.remove(source.path) }
            let target = try fileManager.destinationOfSymbolicLink(atPath: source.path)
            let resolved = URL(
                fileURLWithPath: target,
                relativeTo: source.deletingLastPathComponent()
            ).standardizedFileURL
            try materialize(
                from: resolved,
                to: destination,
                activeSymlinks: &activeSymlinks
            )
            return
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ModelGenerationError.missingSource(source)
        }
        if isDirectory.boolValue {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: []
            ).sorted { $0.path < $1.path }
            for child in children {
                try materialize(
                    from: child,
                    to: destination.appendingPathComponent(child.lastPathComponent),
                    activeSymlinks: &activeSymlinks
                )
            }
        } else {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    static func replaceCandidate(_ candidate: URL, _ destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: candidate)
        } else {
            try fileManager.moveItem(at: candidate, to: destination)
        }
    }

}
