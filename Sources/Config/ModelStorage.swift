import Foundation
import Hub

enum ModelStorage {
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenType/huggingface")
    }

    static var root: URL {
        let path = AppSettings.shared.modelStoragePath
        let url = path.isEmpty ? defaultRoot : URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var huggingFaceBase: URL {
        root
    }

    static var hubModelsBase: URL {
        huggingFaceBase.appendingPathComponent("models")
    }

    static var asrRepositoryBase: URL {
        root.appendingPathComponent("repositories")
    }

    static func mimoASRRepositoryDir() -> URL {
        asrRepositoryBase.appendingPathComponent("XiaomiMiMo/MiMo-V2.5-ASR")
    }

    static var asrRuntimeBase: URL {
        root.appendingPathComponent("runtimes")
    }

    static func localASRRuntimeDir(for provider: LocalASRConfiguration.Provider) -> URL {
        asrRuntimeBase.appendingPathComponent("\(provider.rawValue)-asr")
    }

    static func whisperVariantDir(_ variant: String) -> URL {
        hubModelsBase
            .appendingPathComponent("argmaxinc/whisperkit-coreml")
            .appendingPathComponent(variant)
    }

    static func hubModelRepo(_ modelID: String) -> Hub.Repo {
        Hub.Repo(id: modelID, type: .models)
    }

    static func hubModelRepoDir(_ modelID: String) -> URL {
        HubApi(downloadBase: huggingFaceBase).localRepoLocation(hubModelRepo(modelID))
    }

    static func llmRepoDir(_ modelID: String) -> URL? {
        if let local = localLLMURL(modelID) { return local }
        let dir = hubModelRepoDir(modelID)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    static func installedLLMURL(_ modelID: String) -> URL? {
        guard let dir = llmRepoDir(modelID), llmRepoIsComplete(at: dir) else { return nil }
        return dir
    }

    static func asrRepoDir(_ modelID: String) -> URL? {
        let dir = hubModelRepoDir(modelID)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    static func localWhisperURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localWhisperModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func localLLMURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localLLMModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func whisperModelIsComplete(at dir: URL) -> Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            resourceHasContent(dir.appendingPathComponent("\(name).mlmodelc")) ||
                resourceHasContent(dir.appendingPathComponent("\(name).mlpackage"))
        }
    }

    static func llmRepoIsComplete(at dir: URL) -> Bool {
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

    static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let sz = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(sz)
            }
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

    static func makeLocalID(prefix: String, folderName: String, existing: Set<String>) -> String {
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
