import Foundation

enum TestFixtureRoot {
    static let root: URL = {
        let temporary = ProcessInfo.processInfo.environment["TMPDIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory
        let directory = temporary
            .appendingPathComponent("OpenTypeTests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("Models"), withIntermediateDirectories: true
            )
        } catch {
            fatalError("Cannot create owned test fixtures: \(error)")
        }
        return directory
    }()

    static let history = root.appendingPathComponent("History", isDirectory: true)
    static let models = root.appendingPathComponent("Models", isDirectory: true)
    static let defaultsDomain = root.appendingPathComponent("Defaults").path
    static let defaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: defaultsDomain)!
        defaults.set(models.path, forKey: "modelStoragePath")
        return defaults
    }()
}
