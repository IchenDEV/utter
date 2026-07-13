import Foundation

enum LocalASRRuntime {
    private static let qwenPackage = "qwen3-asr-mlx"
    static let qwenPackageVersion = "0.1.1"
    private static let qwenImport = "qwen3_asr_mlx"
    private static let markerName = ".opentype-runtime-ready"
    private static let nativeMarkerName = ".opentype-native-runtime-ready"

    static func isReady(for provider: LocalASRConfiguration.Provider) -> Bool {
        switch provider {
        case .qwen3:
            let python = qwenPythonURL()
            return FileManager.default.isExecutableFile(atPath: python.path) &&
                qwenMarkerIsCurrent(at: qwenMarkerURL()) &&
                qwenMarkerIsCurrent(at: qwenNativeMarkerURL())
        case .mimo:
            return LocalASRConfiguration.resolvePythonPath() != nil
        }
    }

    static func ensurePythonPath(
        for provider: LocalASRConfiguration.Provider,
        preferredPath: String
    ) async throws -> String {
        switch provider {
        case .qwen3:
            return try await ensureQwenRuntime(preferredPath: preferredPath)
        case .mimo:
            guard let python = LocalASRConfiguration.resolvePythonPath(preferredPath: preferredPath) else {
                throw LocalASRRuntimeError.pythonMissing
            }
            return python
        }
    }

    private static func ensureQwenRuntime(preferredPath: String) async throws -> String {
        let runtimeDir = ModelStorage.qwenASRRuntimeDir()
        let runtimePython = qwenPythonURL().path
        if isReady(for: .qwen3) { return runtimePython }

        if FileManager.default.isExecutableFile(atPath: runtimePython) {
            if !qwenMarkerIsCurrent(at: qwenMarkerURL()) {
                try await installQwenPackage(using: runtimePython)
            }
            try await prepareNativeExtensions(in: runtimeDir)
            try await runProcess(
                executable: runtimePython,
                arguments: ["-c", "import \(qwenImport)"]
            )
            try writeCurrentQwenMarker(to: qwenMarkerURL())
            try writeCurrentQwenMarker(to: qwenNativeMarkerURL())
            return runtimePython
        }

        guard let builderPython = LocalASRConfiguration.resolvePythonPath(preferredPath: preferredPath) else {
            throw LocalASRRuntimeError.pythonMissing
        }

        try? FileManager.default.removeItem(at: runtimeDir)
        try FileManager.default.createDirectory(
            at: runtimeDir.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try await runProcess(executable: builderPython, arguments: ["-m", "venv", runtimeDir.path])
        try await runProcess(
            executable: runtimePython,
            arguments: ["-m", "pip", "install", "--quiet", "--upgrade", "pip", "setuptools", "wheel"]
        )
        try await installQwenPackage(using: runtimePython)
        try await prepareNativeExtensions(in: runtimeDir)
        try await runProcess(
            executable: runtimePython,
            arguments: ["-c", "import \(qwenImport)"]
        )
        try writeCurrentQwenMarker(to: qwenMarkerURL())
        try writeCurrentQwenMarker(to: qwenNativeMarkerURL())
        return runtimePython
    }

    static var qwenRequirement: String {
        "\(qwenPackage)==\(qwenPackageVersion)"
    }

    static func qwenMarkerIsCurrent(_ contents: String?) -> Bool {
        contents?.trimmingCharacters(in: .whitespacesAndNewlines) == qwenRequirement
    }

    private static func qwenMarkerIsCurrent(at url: URL) -> Bool {
        qwenMarkerIsCurrent(try? String(contentsOf: url, encoding: .utf8))
    }

    private static func writeCurrentQwenMarker(to url: URL) throws {
        try Data(qwenRequirement.utf8).write(to: url, options: .atomic)
    }

    private static func installQwenPackage(using python: String) async throws {
        try await runProcess(
            executable: python,
            arguments: ["-m", "pip", "install", "--quiet", "--upgrade", qwenRequirement]
        )
    }

    private static func qwenPythonURL() -> URL {
        ModelStorage.qwenASRRuntimeDir().appendingPathComponent("bin/python")
    }

    private static func qwenMarkerURL() -> URL {
        ModelStorage.qwenASRRuntimeDir().appendingPathComponent(markerName)
    }

    private static func qwenNativeMarkerURL() -> URL {
        ModelStorage.qwenASRRuntimeDir().appendingPathComponent(nativeMarkerName)
    }

    private static func prepareNativeExtensions(in runtimeDir: URL) async throws {
        let nativeExtensions = nativeExtensionURLs(in: runtimeDir)
        for url in nativeExtensions {
            try? await runProcess(
                executable: "/usr/bin/xattr",
                arguments: ["-d", "com.apple.quarantine", url.path]
            )
            try? await runProcess(
                executable: "/usr/bin/xattr",
                arguments: ["-d", "com.apple.provenance", url.path]
            )
            try await runProcess(
                executable: "/usr/bin/codesign",
                arguments: ["-s", "-", "-f", url.path]
            )
        }
    }

    private static func nativeExtensionURLs(in runtimeDir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: runtimeDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            guard ["so", "dylib"].contains(url.pathExtension) else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? url : nil
        }
    }

    private static func runProcess(executable: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
            process.standardError = stderr
            process.terminationHandler = { process in
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: LocalASRRuntimeError.processFailed(message ?? ""))
                    return
                }
                continuation.resume(returning: ())
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum LocalASRRuntimeError: LocalizedError {
    case pythonMissing
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing:
            return L("error.local_asr_python_missing")
        case .processFailed(let message):
            return message.isEmpty ? L("error.local_asr_runtime_failed") : message
        }
    }
}
