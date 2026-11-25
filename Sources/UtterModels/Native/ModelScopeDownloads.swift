import Foundation

package enum ModelScopeError: Error, LocalizedError, Equatable {
    case invalidResponse
    case missingFiles([String])
    case downloadFailed(String)
    case sizeMismatch(String)

    package var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "ModelScope returned an invalid file listing"
        case .missingFiles(let files):
            return "ModelScope is missing required files: \(files.prefix(4).joined(separator: ", "))"
        case .downloadFailed(let message):
            return "ModelScope download failed: \(message)"
        case .sizeMismatch(let file):
            return "ModelScope returned an incomplete file: \(file)"
        }
    }
}

package struct ModelScopeFile: Decodable, Equatable, Sendable {
    package let path: String
    package let size: Int64

    enum CodingKeys: String, CodingKey {
        case path = "Path"
        case size = "Size"
    }
}

package enum ModelScopeDownloads {
    private struct ListingResponse: Decodable {
        let Code: Int
        let Data: ListingData?

        struct ListingData: Decodable {
            let Files: [ModelScopeFile]
        }
    }

    package static func fileList(
        modelID: String,
        revision: String,
        session: URLSession = .shared
    ) async throws -> [ModelScopeFile] {
        var components = URLComponents(string: "https://www.modelscope.cn/api/v1/models/\(modelID)/repo/files")!
        components.queryItems = [URLQueryItem(name: "Revision", value: revision), URLQueryItem(name: "Root", value: "")]
        guard let url = components.url else { throw ModelScopeError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelScopeError.downloadFailed("file listing HTTP error")
        }
        let listing = try JSONDecoder().decode(ListingResponse.self, from: data)
        guard listing.Code == 200, let files = listing.Data?.Files else {
            throw ModelScopeError.invalidResponse
        }
        return files.filter { $0.size >= 0 && !$0.path.isEmpty }
    }

    package static func decodeFileList(_ data: Data) throws -> [ModelScopeFile] {
        let listing = try JSONDecoder().decode(ListingResponse.self, from: data)
        guard listing.Code == 200, let files = listing.Data?.Files else {
            throw ModelScopeError.invalidResponse
        }
        return files.filter { $0.size >= 0 && !$0.path.isEmpty }
    }

    package static func download(
        modelID: String,
        revision: String,
        files: [String],
        to directory: URL,
        session: URLSession = .shared,
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        try Task.checkCancellation()
        let listing = try await fileList(modelID: modelID, revision: revision, session: session)
        let byPath = Dictionary(uniqueKeysWithValues: listing.map { ($0.path, $0) })
        let missing = files.filter { byPath[$0] == nil }
        guard missing.isEmpty else { throw ModelScopeError.missingFiles(missing) }
        let selected = files.compactMap { byPath[$0] }
        let total = selected.reduce(Int64(0)) { $0 + max($1.size, 0) }
        let parent = Progress(totalUnitCount: max(total, 1))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for file in selected {
            try Task.checkCancellation()
            let destination = directory.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if file.size > 0,
               (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(file.size) {
                parent.completedUnitCount += file.size
                progress(parent)
                continue
            }
            let url = fileURL(modelID: modelID, revision: revision, path: file.path)
            var request = URLRequest(url: url)
            request.timeoutInterval = 3_600
            let child = Progress(totalUnitCount: max(file.size, 1), parent: parent, pendingUnitCount: max(file.size, 1))
            try await ModelScopeFileFetch.fetch(
                request: request,
                destination: destination,
                child: child,
                parent: parent,
                onProgress: { _ in progress(parent) }
            )
            child.completedUnitCount = child.totalUnitCount
            progress(parent)
        }
    }

    package static func fileURL(modelID: String, revision: String, path: String) -> URL {
        var components = URLComponents(string: "https://www.modelscope.cn/api/v1/models/\(modelID)/repo")!
        components.queryItems = [
            URLQueryItem(name: "Revision", value: revision),
            URLQueryItem(name: "FilePath", value: path),
        ]
        return components.url!
    }
}

private final class ModelScopeFileFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destination: URL
    private let child: Progress
    private let parent: Progress
    private let onProgress: @Sendable (Progress) -> Void
    private var handle: FileHandle?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var expectedBytes: Int64 = 0
    private var receivedBytes: Int64 = 0
    private var lastReportedBytes: Int64 = 0
    private var reportStep: Int64 = 1
    private var requestError: Error?
    private var continuation: CheckedContinuation<Void, Error>?

    private init(
        destination: URL,
        child: Progress,
        parent: Progress,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) {
        self.destination = destination
        self.child = child
        self.parent = parent
        self.onProgress = onProgress
        self.reportStep = max(1, child.totalUnitCount / 1_000)
    }

    static func fetch(
        request: URLRequest,
        destination: URL,
        child: Progress,
        parent: Progress,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        let fetch = ModelScopeFileFetch(
            destination: destination,
            child: child,
            parent: parent,
            onProgress: onProgress
        )
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                fetch.start(request: request, continuation: continuation)
            }
        } onCancel: {
            fetch.task?.cancel()
        }
    }

    private func start(request: URLRequest, continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
        try? FileManager.default.removeItem(at: destination)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        handle = FileHandle(forWritingAtPath: destination.path)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 3_600
        configuration.timeoutIntervalForResource = 86_400
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            requestError = ModelScopeError.downloadFailed("HTTP error")
            completionHandler(.cancel)
            return
        }
        expectedBytes = max(http.expectedContentLength, 0)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard continuation != nil else { return }
        handle?.write(data)
        receivedBytes += Int64(data.count)
        child.completedUnitCount = receivedBytes
        if receivedBytes - lastReportedBytes >= reportStep {
            lastReportedBytes = receivedBytes
            onProgress(parent)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        handle?.closeFile()
        handle = nil
        session.finishTasksAndInvalidate()
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
            } else {
                continuation.resume(throwing: error)
            }
            return
        }
        if let requestError {
            continuation.resume(throwing: requestError)
            return
        }
        if expectedBytes > 0, receivedBytes != expectedBytes {
            continuation.resume(throwing: ModelScopeError.sizeMismatch(destination.lastPathComponent))
            return
        }
        if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 0, Int64(size) != receivedBytes {
            continuation.resume(throwing: ModelScopeError.sizeMismatch(destination.lastPathComponent))
            return
        }
        continuation.resume()
    }
}
