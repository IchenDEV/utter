import CryptoKit
import Foundation

enum ConfuciusModelDownloader {
    enum Failure: Error {
        case invalidRangeResponse
        case checksumMismatch
    }

    private struct ModelFile {
        let name: String
        let size: Int64
        let sha256: String
    }

    private static let smallFiles: [ModelFile] = [
        .init(name: ".gitattributes", size: 1_570, sha256: "34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930"),
        .init(name: "LICENSE", size: 11_071, sha256: "4d9321cdad58182faa878b015de7d60069881614ddd7571de70f751a9b8e3811"),
        .init(name: "MODEL_LICENSE_zh", size: 7_733, sha256: "18b438311ebb842c15a7c91d9dbb59034efdaf6fff0d105031ef7baf5eeed275"),
        .init(name: "NOTICE", size: 847, sha256: "473880a027d736ca2c9efb3da01cfd30b745d8259e0666b3dea946d4be4b58ef"),
        .init(name: "README.md", size: 2_808, sha256: "7dfc5b13dc96aceb9803ab31c13d5011c6cb6f916ee4472ef96f5d1c8f0abab2"),
        .init(name: "added_tokens.json", size: 1_566, sha256: "de40784677cbd1843cabe5fbee078c7e042cd0b62155f0810af5a13842e5722a"),
        .init(name: "chat_template.json", size: 1_161, sha256: "75a8cfca24f00de72d796fbfed6858fc9614ef3dabd8696684cc3bc03a9c58ff"),
        .init(name: "config.json", size: 7_188, sha256: "1b76b3b6c655fc54595da025f7a96474ad9fa86363303fbdd61a7d8483ccfaf7"),
        .init(name: "generation_config.json", size: 142, sha256: "1da527824d81e07118facff437e03f2e24a23311e3bdeb2368973fe77e5f275c"),
        .init(name: "merges.txt", size: 1_671_853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
        .init(name: "model.safetensors.index.json", size: 78_928, sha256: "b62daee0e37a7bedb8675f69c733eef18a398235ea513f0999f3805d5ac4dedf"),
        .init(name: "preprocessor_config.json", size: 330, sha256: "45e120a4eda2c20c5d7f2ea9354e63536bf35e27aa573fb7cdf78017b378770d"),
        .init(name: "special_tokens_map.json", size: 1_008, sha256: "7b376c510ccf9d88bb9bbee41dfc5052122e16e0dec1124a8d8983c59259a9f3"),
        .init(name: "tokenizer.json", size: 11_429_499, sha256: "0499602714160467f2d68b910651d6216020689f1e016be87a2d0019ee3baeab"),
        .init(name: "tokenizer_config.json", size: 12_487, sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"),
        .init(name: "vocab.json", size: 2_776_833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
    ]

    static func downloadRepository(to directory: URL, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let base = "https://huggingface.co/\(QwenASRModel.confuciusR2T2ID)/resolve/\(QwenASRModel.confuciusRevision)"
        var completedBytes: Int64 = 0
        for file in smallFiles {
            let previousBytes = completedBytes
            try await download(
                to: directory.appendingPathComponent(file.name),
                source: URL(string: "\(base)/\(file.name)")!,
                size: file.size,
                sha256: file.sha256
            ) { onProgress(previousBytes + $0) }
            completedBytes += file.size
        }
        let previousBytes = completedBytes
        try await download(to: directory.appendingPathComponent("model.safetensors")) {
            onProgress(previousBytes + $0)
        }
    }

    static func download(
        to destination: URL,
        session: URLSession? = nil,
        source: URL = URL(string: "https://huggingface.co/\(QwenASRModel.confuciusR2T2ID)/resolve/\(QwenASRModel.confuciusRevision)/model.safetensors")!,
        size: Int64 = QwenASRModel.confuciusWeightBytes,
        sha256: String = QwenASRModel.confuciusWeightSHA256,
        partSize: Int64 = 2 * 1_024 * 1_024,
        maxConcurrent: Int = 16,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let writer = try WeightWriter(destination: destination, size: size)
        let partCount = Int((size + partSize - 1) / partSize)
        // Separate sessions avoid this CDN throttling ranges on one HTTP/2 connection.
        let sessions = session.map { Array(repeating: $0, count: maxConcurrent) }
            ?? (0..<maxConcurrent).map { _ in URLSession(configuration: .ephemeral) }
        defer {
            if session == nil {
                for connection in sessions { connection.invalidateAndCancel() }
            }
        }

        do {
            try await withThrowingTaskGroup(of: (Int, Int64).self) { group in
                var nextPart = 0
                func addPart(_ index: Int, slot: Int) {
                    group.addTask {
                        let offset = Int64(index) * partSize
                        let end = min(offset + partSize, size) - 1
                        let data = try await fetchRange(
                            source: source,
                            start: offset,
                            end: end,
                            size: size,
                            session: sessions[slot]
                        )
                        return (slot, try await writer.write(data, at: offset))
                    }
                }
                for slot in 0..<min(maxConcurrent, partCount) {
                    addPart(nextPart, slot: slot)
                    nextPart += 1
                }
                while let (slot, completedBytes) = try await group.next() {
                    onProgress(completedBytes)
                    if nextPart < partCount {
                        addPart(nextPart, slot: slot)
                        nextPart += 1
                    }
                }
            }
        } catch {
            try? await writer.close()
            throw error
        }
        try await writer.close()
        guard try fileSHA256(destination) == sha256 else {
            throw Failure.checksumMismatch
        }
    }

    private static func fetchRange(
        source: URL,
        start: Int64,
        end: Int64,
        size: Int64,
        session: URLSession
    ) async throws -> Data {
        var lastError: Error = Failure.invalidRangeResponse
        for attempt in 0..<5 {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: source)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 206,
                      http.value(forHTTPHeaderField: "Content-Range") == "bytes \(start)-\(end)/\(size)",
                      Int64(data.count) == end - start + 1 else {
                    throw Failure.invalidRangeResponse
                }
                return data
            } catch {
                lastError = error
                if attempt < 4 {
                    try await Task.sleep(for: .seconds(1 << attempt))
                }
            }
        }
        throw lastError
    }

    private static func fileSHA256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 4 * 1_024 * 1_024), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private actor WeightWriter {
    private let file: FileHandle
    private var completedBytes: Int64 = 0

    init(destination: URL, size: Int64) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        file = try FileHandle(forWritingTo: destination)
        try file.truncate(atOffset: UInt64(size))
    }

    func write(_ data: Data, at offset: Int64) throws -> Int64 {
        try file.seek(toOffset: UInt64(offset))
        try file.write(contentsOf: data)
        completedBytes += Int64(data.count)
        return completedBytes
    }

    func close() throws {
        try file.synchronize()
        try file.close()
    }
}
