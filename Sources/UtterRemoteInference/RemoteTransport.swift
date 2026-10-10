import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

package protocol RemoteTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func shutdown() async
}

package struct URLSessionRemoteTransport: RemoteTransport {
    private let session: URLSession

    package init() { session = URLSession(configuration: .default) }
    package func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
    package func shutdown() async { session.invalidateAndCancel() }
}
