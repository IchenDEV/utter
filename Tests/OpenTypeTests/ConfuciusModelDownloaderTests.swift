import CryptoKit
import Foundation
import XCTest
@testable import OpenType

final class ConfuciusModelDownloaderTests: XCTestCase {
    func testParallelRangesReassembleExactWeightAndReportProgress() async throws {
        let bytes = Data((0..<103).map { UInt8($0) })
        let session = rangeSession(bytes: bytes)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let progress = ProgressValues()

        try await ConfuciusModelDownloader.download(
            to: output,
            session: session,
            source: URL(string: "https://example.test/model.safetensors")!,
            size: Int64(bytes.count),
            sha256: digest(bytes),
            partSize: 16,
            maxConcurrent: 4
        ) { value in
            progress.append(value)
        }

        XCTAssertEqual(try Data(contentsOf: output), bytes)
        XCTAssertEqual(progress.last, Int64(bytes.count))
    }

    func testCorruptRangeCannotPublishAWeight() async throws {
        let bytes = Data((0..<32).map { UInt8($0) })
        let session = rangeSession(bytes: Data(repeating: 0, count: bytes.count))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }

        do {
            try await ConfuciusModelDownloader.download(
                to: output,
                session: session,
                source: URL(string: "https://example.test/model.safetensors")!,
                size: Int64(bytes.count),
                sha256: digest(bytes),
                partSize: 8,
                maxConcurrent: 4
            ) { _ in }
            XCTFail("Corrupted content must fail checksum validation")
        } catch ConfuciusModelDownloader.Failure.checksumMismatch {
        }
    }

    func testFullResponseIsRejectedWhenRangeWasRequested() async throws {
        let bytes = Data((0..<16).map { UInt8($0) })
        let session = rangeSession(bytes: bytes, statusCode: 200)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }

        do {
            try await ConfuciusModelDownloader.download(
                to: output,
                session: session,
                source: URL(string: "https://example.test/model.safetensors")!,
                size: Int64(bytes.count),
                sha256: digest(bytes),
                partSize: 8,
                maxConcurrent: 2
            ) { _ in }
            XCTFail("A full response must not be written as a ranged part")
        } catch ConfuciusModelDownloader.Failure.invalidRangeResponse {
        }
    }

    private func rangeSession(bytes: Data, statusCode: Int = 206) -> URLSession {
        RangeFixtureProtocol.bytes = bytes
        RangeFixtureProtocol.statusCode = statusCode
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class ProgressValues: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64] = []

    func append(_ value: Int64) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var last: Int64? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }
}

private final class RangeFixtureProtocol: URLProtocol {
    static var bytes = Data()
    static var statusCode = 206

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let range = request.value(forHTTPHeaderField: "Range")!
            .replacingOccurrences(of: "bytes=", with: "")
            .split(separator: "-")
        let start = Int(range[0])!
        let end = Int(range[1])!
        let bytes = Self.bytes
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Range": "bytes \(start)-\(end)/\(bytes.count)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes.subdata(in: start..<(end + 1)))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
