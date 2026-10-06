import Foundation

extension SharedVoiceBridge {
    func read<T: Decodable>(_ name: String, limit: Int) throws -> T? {
        try coordinated(name, writing: false) { try self.decode($0, limit: limit) }
    }

    func decode<T: Decodable>(_ url: URL, limit: Int) throws -> T? {
        guard files.fileExists(atPath: url.path) else { return nil }
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw BridgeError.invalidMessage }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw BridgeError.tooLarge }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw BridgeError.invalidMessage }
    }

    func write<T: Encodable>(_ value: T, name: String, limit: Int) throws {
        let data = try encoder.encode(value)
        guard data.count <= limit else { throw BridgeError.tooLarge }
        try coordinated(name, writing: true) { try self.writeData(data, to: $0) }
    }

    func writeData(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    func remove(_ name: String) throws {
        try coordinated(name, writing: true) { url in
            if self.files.fileExists(atPath: url.path) { try self.files.removeItem(at: url) }
        }
    }

    func coordinated<T>(_ name: String, writing: Bool, body: @escaping (URL) throws -> T) throws -> T {
        let url = root.appendingPathComponent(name)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let access: (URL) -> Void = { coordinatedURL in result = Result { try body(coordinatedURL) } }
        let coordinator = NSFileCoordinator()
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError, byAccessor: access)
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError, byAccessor: access)
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BridgeError.io }
        return try result.get()
    }
}
