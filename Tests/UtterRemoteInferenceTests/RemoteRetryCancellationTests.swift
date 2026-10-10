import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import UtterContracts
@testable import UtterRemoteInference

final class RemoteRetryCancellationTests: XCTestCase {
    func testTransportErrorDuringCancelledRetryBecomesCancellation() async throws {
        let transport = RetryFailureTransport(cancelTask: true)
        let client = RemoteLLMClient(transport: transport, log: Log(service: QuietDiagnostics()))
        let task = Task { try await client.generate(remoteRequest()) }
        await transport.waitForRetry()
        await transport.releaseRetry()
        do { _ = try await task.value; XCTFail("Cancelled retry must fail") }
        catch is CancellationError { }
        await client.shutdown()
        let count = await transport.requestCount
        XCTAssertEqual(count, 2)
    }

    func testShutdownDuringRetryDrainsAndNormalizesTransportError() async throws {
        let transport = RetryFailureTransport()
        let client = RemoteLLMClient(transport: transport, log: Log(service: QuietDiagnostics()))
        let task = Task { try await client.generate(remoteRequest()) }
        await transport.waitForRetry()
        let shutdown = Task { await client.shutdown() }
        await transport.waitForShutdown()
        await transport.releaseRetry()
        do { _ = try await task.value; XCTFail("Disposed retry must fail") }
        catch is CancellationError { }
        await shutdown.value
        let count = await transport.requestCount
        XCTAssertEqual(count, 2)
    }
}

private actor RetryFailureTransport: RemoteTransport {
    private let cancelTask: Bool
    private(set) var requestCount = 0
    private var held: CheckedContinuation<Void, Never>?
    private var retryWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopped = false

    init(cancelTask: Bool = false) { self.cancelTask = cancelTask }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        if requestCount == 1 {
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (Data("maximum context length".utf8), response)
        }
        await withCheckedContinuation { continuation in
            held = continuation
            let waiters = retryWaiters
            retryWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        if cancelTask { withUnsafeCurrentTask { $0?.cancel() } }
        throw URLError(.cancelled)
    }

    func waitForRetry() async {
        guard held == nil else { return }
        await withCheckedContinuation { retryWaiters.append($0) }
    }

    func releaseRetry() { held?.resume(); held = nil }

    func shutdown() async {
        stopped = true
        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func waitForShutdown() async {
        guard !stopped else { return }
        await withCheckedContinuation { shutdownWaiters.append($0) }
    }
}
