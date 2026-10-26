import Foundation
import Synchronization
import UtterContracts
import UtterMediaContracts
import UtterModels
import UtterProcessing
import UtterRemoteInference
import UtterRuntime

@MainActor
final class SelectionRemoteOutputFixture {
    let client: RemoteLLMClient
    let processor: TextProcessor
    let options: TextProcessingOptions
    private let transport: SelectionOutputTransport
    let route = UUID().uuidString
    var requests: [URLRequest] { SelectionOutputProtocol.routes.withLock { $0[route]?.requests ?? [] } }

    init(provider: RemoteProvider, body: String, status: Int = 200, holdsResponse: Bool = false) {
        let route = self.route
        SelectionOutputProtocol.routes.withLock { $0[route] = .init(body: body, status: status) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SelectionOutputProtocol.self]
        transport = SelectionOutputTransport(session: URLSession(configuration: configuration), holdsResponse: holdsResponse)
        client = RemoteLLMClient(transport: transport,
            log: Log(service: SelectionOutputLog()))
        var settings = SettingsValues()
        settings.useRemoteLLM = true
        settings.remoteBaseURL = "https://selection.invalid/" + route + "/v1"
        settings.remoteAPIKey = "synthetic-token"
        settings.remoteProvider = provider
        settings.remoteModel = "fixture-model"
        settings.inputLanguage = .english
        options = TextProcessingOptions(settings: settings)
        let dictionary = PersonalDictionarySnapshot(entries: [], editRules: [])
        processor = TextProcessor(providers: SelectionOutputProviders(client: client), imageProviders: nil,
            access: LocalModelAccessGate(), files: WorkflowFiles(), settings: { settings },
            dictionary: { dictionary }, log: Log(service: SelectionOutputLog()))
    }

    func close() async {
        await client.shutdown()
        _ = SelectionOutputProtocol.routes.withLock { $0.removeValue(forKey: route) }
    }
    func releaseResponse() async { await transport.releaseResponse() }
}

private actor SelectionOutputTransport: RemoteTransport {
    let session: URLSession
    let holdsResponse: Bool
    private var released = false
    private var waiting: CheckedContinuation<Void, Never>?
    init(session: URLSession, holdsResponse: Bool) { self.session = session; self.holdsResponse = holdsResponse }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let result = try await session.data(for: request)
        if holdsResponse, !released { await withCheckedContinuation { waiting = $0 } }
        return result
    }
    func releaseResponse() { released = true; waiting?.resume(); waiting = nil }
    func shutdown() async { session.invalidateAndCancel(); releaseResponse() }
}

private final class SelectionOutputProtocol: URLProtocol {
    struct Route {
        let body: String
        let status: Int
        var requests: [URLRequest] = []
    }
    static let routes = Mutex<[String: Route]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "selection.invalid", url.pathComponents.count >= 4,
              let route = Self.routes.withLock({ values -> Route? in
                  let id = url.pathComponents[1]
                  values[id]?.requests.append(request)
                  return values[id]
              }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: route.status,
            httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(route.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class SelectionOutputProviders: ProviderCatalog {
    typealias Request = GenerationPurpose
    typealias Value = any TextGenerationService
    let descriptors = [ProviderDescriptor(id: "generation.remote", displayName: "Fixture", modelLocation: .remote)]
    let client: RemoteLLMClient
    init(client: RemoteLLMClient) { self.client = client }
    func register(_ definition: ProviderDefinition<GenerationPurpose, any TextGenerationService>, scope: PluginScope) throws {
        throw ProviderCatalogError.closed
    }
    func create(id: String, request: GenerationPurpose) async throws -> any TextGenerationService { client }
}

private struct SelectionOutputLog: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
