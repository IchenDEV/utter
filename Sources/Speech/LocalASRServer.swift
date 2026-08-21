import Foundation

enum LocalASRServerResponse: Equatable {
    case ready
    case text(String)
    case error(String)

    /// Serve mode prints exactly one JSON object per line; model libraries can
    /// still emit stray progress lines on stdout, which parse to nil and are
    /// skipped by the reader.
    static func parse(line: String) -> LocalASRServerResponse? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let text = object["text"] as? String {
            return .text(normalizeTranscriptText(text))
        }
        if let message = object["error"] as? String {
            return .error(message)
        }
        if object["ready"] as? Bool == true {
            return .ready
        }
        return nil
    }

    static func normalizeTranscriptText(_ text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = normalized.replacingOccurrences(
            of: "\\s+",
            with: "",
            options: .regularExpression
        )
        let noSpeechPlaceholders: Set<String> = ["（无）", "(无)", "【无】", "[无]"]
        return noSpeechPlaceholders.contains(compact) ? "" : normalized
    }
}

/// Keeps one `local-asr-runner.py --serve` process alive so the ASR model is
/// loaded once instead of on every utterance (which cost 2s+ per recording).
actor LocalASRServer {
    private let configuration: LocalASRConfiguration
    private var process: Process?
    private var requestWriter: FileHandle?
    private var responseLines: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator?
    private var currentRequest: Task<String, Error>?
    private var idleShutdownTask: Task<Void, Never>?

    private static let readyTimeout: TimeInterval = 300
    private static let requestTimeout: TimeInterval = 180
    private static let idleShutdownInterval: TimeInterval = 20 * 60

    init(configuration: LocalASRConfiguration) {
        self.configuration = configuration
    }

    deinit {
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
    }

    func warmUp(runnerURL: URL, pythonPath: String) async {
        do {
            try await ensureServer(runnerURL: runnerURL, pythonPath: pythonPath)
            scheduleIdleShutdown()
        } catch {
            Log.error("[LocalASRServer] \(configuration.logName) warm-up failed: \(error.localizedDescription)")
        }
    }

    func transcribe(
        audioURL: URL,
        language: String?,
        runnerURL: URL,
        pythonPath: String
    ) async throws -> String {
        while let running = currentRequest {
            _ = try? await running.value
        }
        let request = Task {
            try await self.performRequest(
                audioURL: audioURL,
                language: language,
                runnerURL: runnerURL,
                pythonPath: pythonPath
            )
        }
        currentRequest = request
        defer {
            currentRequest = nil
            scheduleIdleShutdown()
        }
        return try await request.value
    }

    private func performRequest(
        audioURL: URL,
        language: String?,
        runnerURL: URL,
        pythonPath: String
    ) async throws -> String {
        try await ensureServer(runnerURL: runnerURL, pythonPath: pythonPath)
        guard let requestWriter else {
            throw LocalASRError.processFailed("local ASR server is unavailable")
        }

        var payload: [String: Any] = ["audio": audioURL.path]
        if let language {
            payload["language"] = language
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        do {
            try requestWriter.write(contentsOf: data + Data("\n".utf8))
        } catch {
            shutdown()
            throw LocalASRError.processFailed("could not reach the local ASR server")
        }

        switch try await nextResponse(timeout: Self.requestTimeout) {
        case .text(let text):
            return text
        case .error(let message):
            throw LocalASRError.processFailed(message)
        case .ready:
            shutdown()
            throw LocalASRError.invalidResponse
        }
    }

    private func ensureServer(runnerURL: URL, pythonPath: String) async throws {
        if let process, process.isRunning, requestWriter != nil { return }

        shutdown()
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = serverArguments(runnerURL: runnerURL)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // Drain stderr so the child never blocks on a full pipe.
        let logName = configuration.logName
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                Log.info("[LocalASRServer] \(logName) stderr: \(message.prefix(400))")
            }
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        try process.run()
        self.process = process
        self.requestWriter = stdin.fileHandleForWriting
        self.responseLines = stdout.fileHandleForReading.bytes.lines.makeAsyncIterator()

        let response = try await nextResponse(timeout: Self.readyTimeout)
        guard response == .ready else {
            shutdown()
            if case .error(let message) = response {
                throw LocalASRError.processFailed(message)
            }
            throw LocalASRError.invalidResponse
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        Log.info("[LocalASRServer] \(configuration.logName) server ready in \(String(format: "%.1f", elapsed))s")
    }

    private func serverArguments(runnerURL: URL) -> [String] {
        var args = [
            "-I", "-B",
            runnerURL.path,
            "--provider", configuration.provider.rawValue,
            "--model", configuration.modelPath,
            "--serve",
        ]
        if !configuration.tokenizerPath.isEmpty {
            args += ["--tokenizer", configuration.tokenizerPath]
        }
        if !configuration.repoPath.isEmpty {
            args += ["--repo", configuration.repoPath]
        }
        return args
    }

    private func nextResponse(timeout: TimeInterval) async throws -> LocalASRServerResponse {
        do {
            while true {
                guard let line = try await withTimeout(timeout, operation: { [weak self] in
                    try await self?.readResponseLine()
                }) ?? nil else {
                    shutdown()
                    throw LocalASRError.processFailed("local ASR server exited unexpectedly")
                }
                if let response = LocalASRServerResponse.parse(line: line) {
                    return response
                }
            }
        } catch let error as LocalASRTimeout {
            let _ = error
            shutdown()
            throw LocalASRError.processFailed("local ASR server timed out")
        }
    }

    private func readResponseLine() async throws -> String? {
        guard var iterator = responseLines else { return nil }
        let line = try await iterator.next()
        responseLines = iterator
        return line
    }

    private func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LocalASRTimeout()
            }
            guard let result = try await group.next() else {
                throw LocalASRTimeout()
            }
            group.cancelAll()
            return result
        }
    }

    private func scheduleIdleShutdown() {
        idleShutdownTask?.cancel()
        idleShutdownTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleShutdownInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.shutdownIfIdle()
        }
    }

    private func shutdownIfIdle() {
        guard currentRequest == nil else { return }
        guard process != nil else { return }
        Log.info("[LocalASRServer] shutting down idle \(configuration.logName) server")
        shutdown()
    }

    private func shutdown() {
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        process = nil
        try? requestWriter?.close()
        requestWriter = nil
        responseLines = nil
    }
}

private struct LocalASRTimeout: Error {}
