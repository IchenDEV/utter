import Foundation
import XCTest
@testable import OpenType

final class LocalASRRuntimeIntegrationTests: XCTestCase {
    func testMigratesInstalledQwenRuntimeToPinnedVersion() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_QWEN_RUNTIME_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_QWEN_RUNTIME_INTEGRATION=1 to run this integration test")
        }

        let python = try await LocalASRRuntime.ensurePythonPath(for: .qwen3, preferredPath: "python3")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: python))
        XCTAssertTrue(LocalASRRuntime.isReady(for: .qwen3))

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-c", "import importlib.metadata as m; print(m.version('qwen3-asr-mlx'))"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let version = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(version, LocalASRRuntime.qwenPackageVersion)
    }
}
