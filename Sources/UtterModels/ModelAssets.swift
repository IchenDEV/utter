import Foundation
import UtterContracts

package enum ModelAssets {
    package static func speechModelIsComplete(at directory: URL?, requiredFiles: [String]) -> Bool {
        guard let directory, !requiredFiles.isEmpty else { return false }
        return requiredFiles.allSatisfy { fileExists(directory.appendingPathComponent($0)) }
    }

    package static func whisperModelIsComplete(at dir: URL) -> Bool {
        whisperWeightsAreComplete(at: dir) && (try? WhisperTokenizerAssets.read(at: dir)) != nil
    }

    package static func whisperWeightsAreComplete(at dir: URL) -> Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            resourceHasContent(dir.appendingPathComponent("\(name).mlmodelc")) ||
                resourceHasContent(dir.appendingPathComponent("\(name).mlpackage"))
        }
    }

    package static func llmRepoIsComplete(at dir: URL) -> Bool {
        guard fileExists(dir.appendingPathComponent("config.json")) else { return false }
        let indexURL = dir.appendingPathComponent("model.safetensors.index.json")
        if fileExists(indexURL),
           let data = try? Data(contentsOf: indexURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weightMap = object["weight_map"] as? [String: String] {
            let shards = Set(weightMap.values)
            return !shards.isEmpty && shards.allSatisfy {
                fileExists(dir.appendingPathComponent($0))
            }
        }

        if fileExists(dir.appendingPathComponent("model.safetensors")) ||
            fileExists(dir.appendingPathComponent("weights.safetensors")) {
            return true
        }

        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "npz",
               fileExists(fileURL) {
                return true
            }
        }
        return false
    }

    package static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  values.isDirectory != true, let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    private static func fileExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0 > 0
    }

    private static func resourceHasContent(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue ? directorySize(at: url) > 0 : fileExists(url)
    }

    package static func makeLocalID(prefix: String, folderName: String, existing: Set<String>) -> String {
        let cleanName = folderName.isEmpty ? "model" : folderName
        let base = "local/\(prefix)-\(cleanName)"
        guard existing.contains(base) else { return base }
        for n in 2...999 {
            let candidate = "\(base)-\(n)"
            if !existing.contains(candidate) { return candidate }
        }
        return "\(base)-\(UUID().uuidString.prefix(8))"
    }
}
