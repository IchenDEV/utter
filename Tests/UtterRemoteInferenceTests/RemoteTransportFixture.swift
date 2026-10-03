import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import UtterContracts
@testable import UtterRemoteInference

struct QuietDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}

actor RemoteTransportFixture: RemoteTransport {
    struct Reply: Sendable {
        let status: Int
        let body: String
    }

    private var replies: [Reply]
    private var requests: [URLRequest] = []
    private var held: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
    private let holdsResponse: Bool
    private var stopped = false

    init(_ replies: [Reply], holdsResponse: Bool = false) {
        self.replies = replies
        self.holdsResponse = holdsResponse
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if holdsResponse { await withCheckedContinuation { held = $0 } }
        let reply = replies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.body.utf8), response)
    }

    func shutdown() async {
        stopped = true
        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func waitUntilStarted() async {
        guard requests.isEmpty else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitUntilShutdown() async {
        guard !stopped else { return }
        await withCheckedContinuation { shutdownWaiters.append($0) }
    }

    func releaseResponse() {
        held?.resume()
        held = nil
    }

    func capturedRequests() -> [URLRequest] { requests }
}

let openAIReply = RemoteTransportFixture.Reply(status: 200, body: #"{"choices":[{"message":{"content":"result"}}]}"#)

func remoteRequest(provider: RemoteProvider = .custom) -> TextGenerationRequest {
    TextGenerationRequest(
        prompt: "spoken text", systemPrompt: "format text", modelID: "fixture-model",
        remote: RemoteGenerationConfiguration(baseURL: "https://example.invalid/v1/", apiKey: "fixture-token", provider: provider)
    )
}
