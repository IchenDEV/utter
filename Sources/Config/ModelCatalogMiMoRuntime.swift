import Foundation

@MainActor
extension ModelCatalog {
    static func mimoRepositoryIsReady(at dir: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("src/mimo_audio/mimo_audio.py").path
        )
    }
}
