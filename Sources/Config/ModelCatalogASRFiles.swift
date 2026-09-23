import Foundation

extension ModelCatalog {
    static func asrRepoContainsRequiredFiles(_ id: String, at dir: URL?) -> Bool {
        guard let dir else { return false }
        return asrRequiredFiles(for: id).allSatisfy { relativePath in
            let file = dir.appendingPathComponent(relativePath)
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return false }
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0 > 0
        }
    }

    nonisolated static func asrRequiredFiles(for id: String) -> [String] {
        switch id {
        case QwenASRModel.defaultID, QwenASRModel.confuciusR2T2ID:
            var required = [
                "config.json",
                "model.safetensors",
                "model.safetensors.index.json",
                "preprocessor_config.json",
                "tokenizer_config.json",
                "vocab.json",
                "merges.txt",
            ]
            if id == QwenASRModel.confuciusR2T2ID {
                required += ["LICENSE", "MODEL_LICENSE_zh", "NOTICE"]
            }
            return required
        case "mlx-community/FireRedASR2-AED-mlx":
            return ["config.json", "tokenizer.json"]
        case "mlx-community/Mega-ASR-6bit":
            return ["config.json", "tokenizer_config.json"]
        default:
            return ["config.json"]
        }
    }
}
