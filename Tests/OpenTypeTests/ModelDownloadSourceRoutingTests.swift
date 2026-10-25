import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterMLX
@testable import UtterModels
import UtterPresentationContracts

@MainActor
final class ModelDownloadSourceRoutingTests: XCTestCase {
    func testProductionRequestsUseSelectedSourceWithoutLeakingCredentials() async throws {
        let canary = "utter-download-source-synthetic-token"
        guard ProcessInfo.processInfo.environment["UTTER_SOURCE_REQUEST_CHILD"] == "1" else {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            child.arguments = ["xctest", "-XCTest",
                "OpenTypeTests.ModelDownloadSourceRoutingTests/testProductionRequestsUseSelectedSourceWithoutLeakingCredentials",
                Bundle(for: Self.self).bundleURL.path]
            var environment = ProcessInfo.processInfo.environment
            environment["UTTER_SOURCE_REQUEST_CHILD"] = "1"
            environment["HF_TOKEN"] = canary
            child.environment = environment
            child.standardOutput = FileHandle.standardOutput
            child.standardError = FileHandle.standardError
            try child.run()
            for _ in 0..<600 where child.isRunning {
                try await Task.sleep(for: .milliseconds(100))
            }
            if child.isRunning { child.terminate(); XCTFail("Request capture exceeded 60 seconds") }
            child.waitUntilExit()
            XCTAssertEqual(child.terminationStatus, 0)
            return
        }

        URLProtocol.registerClass(ModelSourceRequestProtocol.self)
        defer { URLProtocol.unregisterClass(ModelSourceRequestProtocol.self) }
        for source in ModelDownloadSource.allCases {
            let fixture = try SourceCatalogFixture(source: source)
            let whisper = try XCTUnwrap(fixture.catalog.whisperModels.first?.id)
            let operations: [(String, () async throws -> Void)] = [
                ("whisperkit-coreml", { await fixture.catalog.downloadWhisper(whisper) }),
                ("utter-source/recognizer", { await fixture.catalog.downloadASR("utter-source/recognizer") }),
                ("utter-source/formatter", { await fixture.catalog.downloadLLM("utter-source/formatter") }),
                (QwenASRModel.confuciusR2T2ID, {
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.protocolClasses = [ModelSourceRequestProtocol.self]
                    let session = URLSession(configuration: configuration)
                    defer { session.invalidateAndCancel() }
                    try await ConfuciusModelDownloader.downloadRepository(to: fixture.root.appendingPathComponent("confucius"),
                        source: source, session: session) { _ in }
                }),
                ("openai/whisper-", {
                    let staging = ModelStorage.generationStaging(for: UUID(), storageRoot: fixture.root)
                    try ModelStorage.prepareGeneration(staging)
                    defer { ModelStorage.removeGenerationStaging(staging) }
                    try await fixture.catalog.installWhisperTokenizer(model: whisper, directory: staging.downloadBase,
                                                                     staging: staging, source: source)
                }),
            ]
            for (path, operation) in operations {
                FileHandle.standardError.write(Data("[Source request] \(source.rawValue) \(path)\n".utf8))
                ModelSourceRequestProtocol.reset()
                do { try await operation() } catch { }
                let requests = ModelSourceRequestProtocol.requests
                XCTAssertFalse(requests.isEmpty, "No request captured for \(path)")
                XCTAssertTrue(requests.contains { $0.url?.path.contains(path) == true }, path)
                XCTAssertTrue(requests.allSatisfy { $0.url?.host == URL(string: source.endpoint)?.host }, path)
                if source == .hfMirror {
                    XCTAssertTrue(requests.allSatisfy { !($0.value(forHTTPHeaderField: "Authorization") ?? "").contains(canary) })
                } else if path != QwenASRModel.confuciusR2T2ID {
                    XCTAssertTrue(requests.contains { ($0.value(forHTTPHeaderField: "Authorization") ?? "").contains(canary) })
                }
            }
            XCTAssertTrue(fixture.catalog.llmModels.first?.status.isError == true)
            XCTAssertTrue(fixture.catalog.asrModels.first { $0.id == "utter-source/recognizer" }?.status.isError == true)
            await fixture.catalog.close()
            fixture.remove()
        }

        let fixture = try SourceCatalogFixture(source: .hfMirror)
        FileHandle.standardError.write(Data("[Source request] frozen multi-repository source\n".utf8))
        ModelSourceRequestProtocol.reset()
        ModelSourceRequestProtocol.respond = { transport in
            Task { @MainActor in
                fixture.settings.modelDownloadSource = .huggingFace
                transport.finish(Data("{\"siblings\":[]}".utf8))
            }
        }
        await fixture.catalog.downloadASR("utter-source/pair")
        let pairRequests = ModelSourceRequestProtocol.requests
        XCTAssertTrue(pairRequests.contains { $0.url?.path.contains("utter-source/first") == true })
        XCTAssertTrue(pairRequests.contains { $0.url?.path.contains("utter-source/second") == true })
        XCTAssertTrue(pairRequests.allSatisfy { $0.url?.host == "hf-mirror.com" })
        ModelSourceRequestProtocol.reset()
        await fixture.catalog.downloadASR("utter-source/recognizer")
        XCTAssertTrue(ModelSourceRequestProtocol.requests.allSatisfy { $0.url?.host == "huggingface.co" })
        XCTAssertFalse(ModelSourceRequestProtocol.requests.isEmpty)
        await fixture.catalog.close()
        fixture.remove()
    }
}

@MainActor
private struct SourceCatalogFixture {
    let name = "ModelSource-\(UUID().uuidString)"
    let defaults: UserDefaults
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let settings: AppSettings
    let catalog: ModelCatalog

    init(source: ModelDownloadSource) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let service = SettingsStore(defaults: defaults)
        let storageRoot = root
        service.update { $0.modelStoragePath = storageRoot.path; $0.modelDownloadSource = source }
        settings = AppSettings(service: service)
        let artifacts = [
            ModelArtifact(id: "utter-source/formatter", kind: .llm, displayName: "Formatter"),
            ModelArtifact(id: "utter-source/recognizer", kind: .asr, displayName: "Recognizer", requiredFiles: ["config.json"]),
            ModelArtifact(id: QwenASRModel.confuciusR2T2ID, kind: .asr, displayName: "Confucius", requiredFiles: ["config.json"]),
            ModelArtifact(id: "utter-source/pair", kind: .asr, displayName: "Pair", requiredFiles: ["config.json"],
                          repositories: ["utter-source/first", "utter-source/second"]),
        ]
        catalog = ModelCatalog(settings: settings, log: Log(service: SourceTestDiagnostics()), access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(download: { id, source, staging, progress in
                try await MLXModelDownloads.download(id, source: source, downloadBase: staging.downloadBase,
                                                     cache: staging.hubCache, progress: progress)
            }, validate: { _ in }), artifacts: artifacts, startupStorageRoot: root)
    }

    func remove() {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: root)
    }
}

private struct SourceTestDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}

private final class ModelSourceRequestProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var captured: [URLRequest] = []
    static var respond: ((ModelSourceRequestProtocol) -> Void)?

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    static func reset() {
        lock.lock()
        captured = []
        respond = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let respond = Self.respond
        Self.lock.unlock()
        if let respond { respond(self) }
        else { finish(Data("{\"error\":\"fixture\"}".utf8), statusCode: 401) }
    }

    func finish(_ data: Data, statusCode: Int = 200) {
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil,
                                      headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
