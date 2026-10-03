import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import UtterContracts
@testable import UtterRemoteInference

final class RemoteTransportTests: XCTestCase {
    func testOpenAIWireRequest() async throws {
        let transport = RemoteTransportFixture([openAIReply])
        let client = RemoteLLMClient(transport: transport, log: Log(service: QuietDiagnostics()))
        let result = try await client.generate(remoteRequest())
        XCTAssertEqual(result, "result")
        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "fixture-model")
        XCTAssertEqual(body["max_tokens"] as? Int, 2048)
        XCTAssertEqual((body["messages"] as? [[String: String]])?.map { $0["role"] }, ["system", "user"])
        await client.shutdown()
    }

    func testAnthropicWireRequest() async throws {
        let transport = RemoteTransportFixture([.init(status: 200, body: #"{"content":[{"type":"text","text":"result"}]}"#)])
        let client = RemoteLLMClient(transport: transport, log: Log(service: QuietDiagnostics()))
        let result = try await client.generate(remoteRequest(provider: .claude))
        XCTAssertEqual(result, "result")
        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "fixture-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["system"] as? String, "format text")
        await client.shutdown()
    }

    func testContextErrorRetriesOnceWithReducedBudget() async throws {
        for status in [400, 413, 422] {
            let transport = RemoteTransportFixture([.init(status: status, body: "maximum context length"), openAIReply])
            let client = RemoteLLMClient(transport: transport, log: Log(service: QuietDiagnostics()))
            let result = try await client.generate(remoteRequest())
            XCTAssertEqual(result, "result")
            let requests = await transport.capturedRequests()
            XCTAssertEqual(requests.count, 2)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests.last?.httpBody)) as? [String: Any])
            XCTAssertEqual(body["max_tokens"] as? Int, 1024)
            await client.shutdown()
        }
    }

    func testServerAndUnsupportedParameterErrorsNeverRetry() async throws {
        for reply in [
            RemoteTransportFixture.Reply(status: 503, body: "maximum context length"),
            .init(status: 400, body: "unsupported parameter: max_tokens, use max_completion_tokens"),
        ] {
            let transport = RemoteTransportFixture([reply])
            let client = RemoteLLMClient(transport: transport, log: Log(service: QuietDiagnostics()))
            do { _ = try await client.generate(remoteRequest()); XCTFail("Request should fail") }
            catch RemoteLLMError.requestFailed { }
            let requests = await transport.capturedRequests()
            XCTAssertEqual(requests.count, 1)
            await client.shutdown()
        }
    }

    func testCancellationRejectsLateResponseWithoutRetry() async throws {
        let transport = RemoteTransportFixture([.init(status: 400, body: "maximum context length")], holdsResponse: true)
        let client = RemoteLLMClient(transport: transport, log: Log(service: QuietDiagnostics()))
        let task = Task { try await client.generate(remoteRequest()) }
        await transport.waitUntilStarted()
        task.cancel()
        await transport.releaseResponse()
        do { _ = try await task.value; XCTFail("Cancelled request should fail") }
        catch is CancellationError { }
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        await client.shutdown()
    }

    func testShutdownDrainsLateResponseAndClosesAdmission() async throws {
        let transport = RemoteTransportFixture([openAIReply], holdsResponse: true)
        let client = RemoteLLMClient(transport: transport, log: Log(service: QuietDiagnostics()))
        let task = Task { try await client.generate(remoteRequest()) }
        await transport.waitUntilStarted()
        let shutdown = Task { await client.shutdown() }
        await transport.waitUntilShutdown()
        do { _ = try await client.generate(remoteRequest()); XCTFail("Closed client should reject ingress") }
        catch is CancellationError { }
        await transport.releaseResponse()
        do { _ = try await task.value; XCTFail("Disposed client should reject late response") }
        catch is CancellationError { }
        await shutdown.value
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }
}
