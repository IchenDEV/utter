import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterModels
import UtterProcessing
import UtterRuntime

@MainActor
final class ProcessingPluginTests: XCTestCase {
    func testCustomTransformationAllowsDeletionAndRequiresFactSupport() async throws {
        let source = "Alice has 2 tasks. Review is complete. No refund was promised."
        let cases: [(String, String, ProcessingDecision.Disposition)] = [
            ("Review complete.", #"{"decision":"supported","added_facts":[]}"#, .accepted),
            ("I promise a refund.", #"{"decision":"unsupported","added_facts":["refund promise"]}"#, .fallback),
            ("Review complete.", "unparseable", .fallback),
        ]
        for (candidate, verdict, expected) in cases {
            try await withFixture(outputs: [candidate, verdict]) { runtime, backend, _ in
                let base = self.request(text: source)
                var options = base.options
                options.languageStyle = .custom
                options.customStylePrompt = "Summarize freely without adding facts."
                let result = try await runtime.service(ProcessingServices.text).process(ProcessingRequest(
                    mode: .formatting, text: source, options: options, dictionary: base.dictionary,
                    collectsDiagnostics: true))
                XCTAssertEqual(result.decision.disposition, expected)
                XCTAssertEqual(result.text, expected == .accepted ? candidate : source)
                XCTAssertEqual(result.trace?.candidate, candidate)
                let calls = await backend.requests
                XCTAssertEqual(calls.count, 2)
                XCTAssertTrue(calls[1].systemPrompt?.contains("Deleting") == true)
                XCTAssertEqual(calls[0].modelID, calls[1].modelID)
                XCTAssertEqual(calls[0].modelURL, calls[1].modelURL)
            }
        }
    }

    func testCancellationDuringFactSupportCannotPublishTheCandidate() async throws {
        try await withFixture(outputs: ["Review complete.", #"{"decision":"supported","added_facts":[]}"#],
                              holdAtCall: 2) { runtime, backend, _ in
            let base = self.request(text: "Review is complete after checking all the tasks.")
            var options = base.options
            options.languageStyle = .custom
            options.customStylePrompt = "Keep the conclusion."
            let operation = Task {
                try await runtime.service(ProcessingServices.text).process(ProcessingRequest(mode: .formatting,
                    text: base.text, options: options, dictionary: base.dictionary))
            }
            await backend.waitUntilStarted()
            operation.cancel()
            await backend.release()
            do { _ = try await operation.value; XCTFail("Cancelled verifier published output") }
            catch is CancellationError { }
        }
    }

    func testProductionDiagnosticsExposeNumericAcceptanceAndSilentFallback() async throws {
        for (output, disposition) in [("周五下午 3 点", ProcessingDecision.Disposition.accepted),
                                      ("周五下午 4 点", .fallback)] {
            try await withFixture(output: output) { runtime, _, _ in
                let base = self.request(text: "周五下午三点")
                let request = ProcessingRequest(mode: .formatting, text: base.text,
                    options: base.options, dictionary: base.dictionary, collectsDiagnostics: true)
                let result = try await runtime.service(ProcessingServices.text).process(request)
                XCTAssertEqual(result.decision.disposition, disposition)
                XCTAssertEqual(result.trace?.candidate, output)
                XCTAssertEqual(result.trace?.generations.first?.output, output)
                XCTAssertEqual(result.text, disposition == .accepted ? output : base.text)
            }
        }
    }

    func testDirectModeUsesFrozenDictionaryWithoutCallingGeneration() async throws {
        try await withFixture { runtime, backend, _ in
            let service = try runtime.service(ProcessingServices.text)
            let dictionary = PersonalDictionarySnapshot(entries: [DictionaryEntry(original: "helo", replacement: "hello")], editRules: [])
            let store = try runtime.service(DataServices.dictionary)
            store.addEntry(original: "helo", replacement: "different")
            let result = try await service.process(self.request(mode: .direct, text: "helo", dictionary: dictionary))
            XCTAssertEqual(result.text, "hello")
            let calls = await backend.requests
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testFormattingUsesRegisteredProviderWithoutImageRegistry() async throws {
        try await withFixture { runtime, backend, _ in
            let service = try runtime.service(ProcessingServices.text)
            let result = try await service.process(self.request())
            XCTAssertEqual(result.text, "hello")
            let calls = await backend.requests
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.first?.modelID, "fixture-model")
            XCTAssertEqual(calls.first?.modelURL?.path, "/fixture-model")
        }
    }

    func testShutdownDrainsIgnoredCancellationBeforeProviderDisposal() async throws {
        try await withFixture(holdsResponse: true) { runtime, backend, lifetime in
            let service = try runtime.service(ProcessingServices.text)
            let operation = Task { try await service.process(self.request()) }
            await backend.waitUntilStarted()
            let shutdown = Task { try await runtime.stop() }
            for _ in 0..<1_000 {
                if runtime.state == .stopping { break }
                await Task.yield()
            }
            XCTAssertEqual(runtime.state, .stopping)
            XCTAssertFalse(lifetime.disposed)
            do { _ = try await service.process(self.request(mode: .direct)); XCTFail("Revoked service accepted ingress") }
            catch is CancellationError { }
            await backend.release()
            do { _ = try await operation.value; XCTFail("Cancelled generation published output") }
            catch is CancellationError { }
            try await shutdown.value
            XCTAssertTrue(lifetime.disposed)
            do { _ = try await service.process(self.request()); XCTFail("Retained service accepted ingress") }
            catch is CancellationError { }
        }
    }

    func testExplicitProviderAndFrozenPathOverrideLegacyFlagsAcrossAnAwait() async throws {
        try await withFixture(holdsResponse: true) { runtime, backend, _ in
            let service = try runtime.service(ProcessingServices.text)
            var preferences = SettingsValues()
            preferences.useRemoteLLM = true
            preferences.localLLMBackend = .espresso
            preferences.remoteModel = "legacy-remote"
            var options = TextProcessingOptions(settings: preferences, inputLanguage: .english)
            options.textProviderID = "fixture.processing"
            options.llmModel = "admitted-model"
            options.modelLocations = .frozen(bundle: nil, directory: URL(fileURLWithPath: "/admitted-model"))
            let request = ProcessingRequest(mode: .formatting, text: "hello", options: options,
                dictionary: PersonalDictionarySnapshot(entries: [], editRules: []))
            let operation = Task { try await service.process(request) }
            await backend.waitUntilStarted()
            try runtime.service(DataServices.settings).update { $0.modelStoragePath = "/later-root" }
            await backend.release()
            _ = try await operation.value
            let requests = await backend.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.modelID, "admitted-model")
            XCTAssertEqual(requests.first?.modelURL?.path, "/admitted-model")
            XCTAssertNil(requests.first?.remote)
        }
    }

    private func request(
        mode: TextProcessingMode = .formatting, text: String = "hello",
        dictionary: PersonalDictionarySnapshot = PersonalDictionarySnapshot(entries: [], editRules: [])
    ) -> ProcessingRequest {
        var options = TextProcessingOptions(settings: SettingsValues(), inputLanguage: .english)
        options.textProviderID = "fixture.processing"
        options.llmModel = "fixture-model"
        return ProcessingRequest(mode: mode, text: text, options: options, dictionary: dictionary)
    }

    private func withFixture(
        holdsResponse: Bool = false, output: String = "hello", outputs: [String]? = nil, holdAtCall: Int? = nil,
        _ operation: (PluginRuntime, ProcessingFixtureBackend, ProviderLifetime) async throws -> Void
    ) async throws {
        let name = "ProcessingPlugin-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        let backend = ProcessingFixtureBackend(holdsResponse: holdsResponse,
            outputs: outputs ?? [output], holdAtCall: holdAtCall)
        let lifetime = ProviderLifetime()
        let provider = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.processing", requires: [GenerationServices.providers.required],
            provides: [ModelServices.files.reference, GenerationServices.mlx.reference]
        )) { context, _ in
            let registry = try context.require(GenerationServices.providers)
            let descriptor = ProviderDescriptor(id: "fixture.processing", displayName: "Fixture")
            try registry.register(ProviderDefinition(descriptor: descriptor) { _ in backend }, scope: context.scope)
            try context.scope.onDispose { lifetime.disposed = true }
            try context.provide(ModelServices.files, value: ProcessingFixtureFiles())
            try context.provide(GenerationServices.mlx, value: descriptor)
        }
        let plugins = [
            DataPlugins.settings(defaults: defaults), DataPlugins.dictionary(directoryURL: directory),
            DataPlugins.lexicons(), DataPlugins.diagnostics(ProcessingFixtureDiagnostics()),
            ModelPlugins.resourceAccess(), ModelPlugins.textProviders(), provider, ProcessingPlugins.text(),
        ]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        do { try await operation(runtime, backend, lifetime) }
        catch { await backend.release(); try? await runtime.stop(); throw error }
        try await runtime.stop()
    }
}

@MainActor
private final class ProviderLifetime { var disposed = false }

private actor ProcessingFixtureBackend: TextGenerationService {
    private let holdsResponse: Bool
    private let outputs: [String]
    private let holdAtCall: Int?
    private var held: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requests: [TextGenerationRequest] = []
    init(holdsResponse: Bool, outputs: [String], holdAtCall: Int?) {
        self.holdsResponse = holdsResponse; self.outputs = outputs; self.holdAtCall = holdAtCall
    }
    func generate(_ request: TextGenerationRequest) async throws -> String {
        requests.append(request)
        if holdsResponse || requests.count == holdAtCall {
            await withCheckedContinuation { continuation in
                held = continuation
                let pending = waiters; waiters.removeAll()
                for waiter in pending { waiter.resume() }
            }
        }
        return outputs[min(requests.count - 1, outputs.count - 1)]
    }
    func waitUntilStarted() async {
        guard held == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { held?.resume(); held = nil }
}

private struct ProcessingFixtureFiles: ModelFilesService {
    func installedTextModelURL(_ id: String) -> URL? { URL(fileURLWithPath: "/fixture-model") }
    func installedSpeechModelURL(_ id: String) -> URL? { nil }
    func speechRequiredFiles(_ id: String) -> [String] { [] }
    func textModelIsComplete(at url: URL) -> Bool { false }
    func installedWhisperURL(_ id: String) -> URL? { nil }
    func whisperVariantURL(_ id: String) -> URL { URL(fileURLWithPath: "/missing") }
    func whisperModelIsComplete(at url: URL) -> Bool { false }
}

private struct ProcessingFixtureDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
