import Foundation

struct OfflineModelManifest: Codable, Equatable, Sendable {
    struct Artifact: Codable, Equatable, Sendable {
        let id: String
        let path: String
    }

    let schemaVersion: Int
    let editionID: String
    let minimumMemoryGB: Int
    let speech: Artifact
    let speechRuntime: Artifact
    let formatting: Artifact
}

struct OfflineModelPaths: Equatable, Sendable {
    let speech: URL
    let speechRuntime: URL
    let formatting: URL
}

enum OfflineModelBundleValidation: Equatable, Sendable {
    case ready(OfflineModelPaths)
    case missingBundle
    case invalidManifest
    case profileMismatch
    case incompleteSpeechModel
    case incompleteSpeechRuntime
    case incompleteFormattingModel
    case missingLegalNotices

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var localizedMessage: String {
        switch self {
        case .ready:
            return L("offline_bundle.ready")
        case .missingBundle:
            return L("offline_bundle.missing")
        case .invalidManifest:
            return L("offline_bundle.invalid_manifest")
        case .profileMismatch:
            return L("offline_bundle.profile_mismatch")
        case .incompleteSpeechModel:
            return L("offline_bundle.incomplete_speech")
        case .incompleteSpeechRuntime:
            return L("offline_bundle.incomplete_speech_runtime")
        case .incompleteFormattingModel:
            return L("offline_bundle.incomplete_formatting")
        case .missingLegalNotices:
            return L("offline_bundle.missing_legal_notices")
        }
    }
}

enum OfflineModelBundle {
    static let directoryName = "OfflineModels"
    static let manifestFilename = "manifest.json"

    static func root(resourceURL: URL? = Bundle.main.resourceURL) -> URL? {
        resourceURL?.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func validate(resourceURL: URL? = Bundle.main.resourceURL) -> OfflineModelBundleValidation {
        guard let root = root(resourceURL: resourceURL) else { return .missingBundle }
        return validate(rootURL: root)
    }

    static func validate(rootURL: URL) -> OfflineModelBundleValidation {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .missingBundle
        }

        let manifestURL = rootURL.appendingPathComponent(manifestFilename)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(OfflineModelManifest.self, from: data),
              manifest.schemaVersion == 2,
              safeRelativePath(manifest.speech.path),
              safeRelativePath(manifest.speechRuntime.path),
              safeRelativePath(manifest.formatting.path) else {
            return .invalidManifest
        }

        let profile = ProductEdition.current
        guard manifest.editionID == profile.id,
              manifest.minimumMemoryGB == profile.minimumMemoryGB,
              manifest.speech.id == profile.speechModel.id,
              manifest.speechRuntime.id == profile.speechRuntime.id,
              manifest.formatting.id == profile.formattingModel.id,
              manifest.speech.path == profile.speechModel.relativePath,
              manifest.speechRuntime.path == profile.speechRuntime.relativePath,
              manifest.formatting.path == profile.formattingModel.relativePath else {
            return .profileMismatch
        }

        let speechURL = rootURL.appendingPathComponent(manifest.speech.path, isDirectory: true)
        guard ModelStorage.qwenASRModelIsComplete(at: speechURL) else {
            return .incompleteSpeechModel
        }
        let speechRuntimeURL = rootURL.appendingPathComponent(
            manifest.speechRuntime.path,
            isDirectory: true
        )
        guard qwenRuntimeIsComplete(at: speechRuntimeURL) else {
            return .incompleteSpeechRuntime
        }
        let formattingURL = rootURL.appendingPathComponent(manifest.formatting.path, isDirectory: true)
        guard ModelStorage.llmRepoIsComplete(at: formattingURL) else {
            return .incompleteFormattingModel
        }
        guard resourceHasContent(rootURL.appendingPathComponent("LICENSES", isDirectory: true)),
              resourceHasContent(rootURL.appendingPathComponent("NOTICE")) else {
            return .missingLegalNotices
        }
        return .ready(OfflineModelPaths(
            speech: speechURL,
            speechRuntime: speechRuntimeURL,
            formatting: formattingURL
        ))
    }

    static func configuredPaths(resourceURL: URL? = Bundle.main.resourceURL) -> OfflineModelPaths? {
        guard case .ready(let paths) = validate(resourceURL: resourceURL) else { return nil }
        return paths
    }

    private static func safeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/").contains("..")
    }

    private static func resourceHasContent(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        if !isDirectory.boolValue {
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return (size ?? 0) > 0
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, (values?.fileSize ?? 0) > 0 { return true }
        }
        return false
    }

    private static func qwenRuntimeIsComplete(at root: URL) -> Bool {
        let python = root.appendingPathComponent("bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return false }
        let markerNames = [".opentype-runtime-ready", ".opentype-native-runtime-ready"]
        return markerNames.allSatisfy { name in
            let contents = try? String(
                contentsOf: root.appendingPathComponent(name),
                encoding: .utf8
            )
            return LocalASRRuntime.qwenMarkerIsCurrent(contents)
        }
    }
}
