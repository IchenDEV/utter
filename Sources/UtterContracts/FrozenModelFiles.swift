import Foundation

/// Captures path selection without retaining access to mutable model preferences.
package struct FrozenModelFiles: ModelFilesService {
    package let revision: String
    private let modelID: String
    private let speechURL: URL?
    private let textURL: URL?
    private let whisperURL: URL?
    private let variantURL: URL
    private let requiredFiles: [String]
    private let validation: any ModelFilesService

    package init(modelID: String, using files: any ModelFilesService) {
        self.modelID = modelID
        speechURL = files.installedSpeechModelURL(modelID)
        textURL = files.installedTextModelURL(modelID)
        whisperURL = files.installedWhisperURL(modelID)
        variantURL = files.whisperVariantURL(modelID)
        requiredFiles = files.speechRequiredFiles(modelID)
        validation = files
        revision = Self.identity([speechURL, textURL, whisperURL])
    }

    package var isCurrent: Bool { revision == Self.identity([speechURL, textURL, whisperURL]) }

    private static func identity(_ urls: [URL?]) -> String {
        urls.map { url in
            guard let url else { return "missing" }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return url.path + ":missing" }
            let device = attributes[.systemNumber] as? NSNumber
            let inode = attributes[.systemFileNumber] as? NSNumber
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
            return url.path + ":" + String(describing: device) + ":" + String(describing: inode)
                + ":" + String(describing: modified)

        }.joined(separator: "|")
    }

    package func installedTextModelURL(_ id: String) -> URL? { id == modelID ? textURL : nil }
    package func installedSpeechModelURL(_ id: String) -> URL? { id == modelID ? speechURL : nil }
    package func speechRequiredFiles(_ id: String) -> [String] { id == modelID ? requiredFiles : [] }
    package func installedWhisperURL(_ id: String) -> URL? { id == modelID ? whisperURL : nil }
    package func whisperVariantURL(_ id: String) -> URL { variantURL }
    package func textModelIsComplete(at url: URL) -> Bool { validation.textModelIsComplete(at: url) }
    package func whisperModelIsComplete(at url: URL) -> Bool { validation.whisperModelIsComplete(at: url) }
}
