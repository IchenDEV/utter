import Foundation

@MainActor
extension ModelCatalog {
    func estimatedLLMDownloadBytes(_ id: String) -> Int64? {
        if let bytes = Self.defaultDownloadEstimateBytes(for: id) { return bytes }
        guard let model = llmModels.first(where: { $0.id == id }) else { return nil }
        return Self.estimatedDownloadBytes(from: model.hint)
    }

    func estimatedASRDownloadBytes(_ id: String) -> Int64? {
        if let bytes = Self.defaultDownloadEstimateBytes(for: id) { return bytes }
        guard let model = asrModels.first(where: { $0.id == id }) else { return nil }
        return Self.estimatedDownloadBytes(from: model.hint)
    }

    static func defaultDownloadEstimateBytes(for id: String) -> Int64? {
        defaultDownloadEstimateBytes[id]
    }

    static func estimatedDownloadBytes(from text: String) -> Int64? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = downloadEstimateRegex.matches(in: text, range: range).last,
              match.numberOfRanges == 3,
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = parseDownloadEstimateValue(String(text[valueRange])) else { return nil }

        let unit = text[unitRange].uppercased()
        guard let multiplier = downloadEstimateMultiplier(for: unit) else { return nil }
        let bytes = value * multiplier
        guard bytes.isFinite, bytes > 0, bytes <= Double(Int64.max) else { return nil }
        return Int64(bytes)
    }

    private static let defaultDownloadEstimateBytes: [String: Int64] = [
        "mlx-community/Qwen3.5-0.8B-MLX-4bit": 652_027_143,
        "mlx-community/Qwen3.5-2B-4bit": 1_749_079_691,
        "mlx-community/Qwen3.5-9B-5bit": 7_096_163_574,
        "mlx-community/Qwen3-30B-A3B-4bit": 17_190_783_781,
        "mlx-community/Qwen3.5-35B-A3B-4bit": 20_418_622_319,
        "mlx-community/Qwen2.5-0.5B-Instruct-4bit": 289_598_797,
        "mlx-community/Qwen2.5-1.5B-Instruct-4bit": 880_169_797,
        "mlx-community/Qwen2.5-3B-Instruct-4bit": 1_747_849_050,
        "mlx-community/Qwen3-0.6B-4bit": 351_383_618,
        "mlx-community/Qwen3-1.7B-4bit": 984_013_244,
        "mlx-community/Qwen3-4B-4bit": 2_278_969_756,
        "mlx-community/gemma-4-e2b-it-4bit": 3_613_528_388,
        "mlx-community/gemma-4-e4b-it-4bit": 5_249_809_327,
        "mlx-community/gemma-3-1b-it-4bit": 771_860_852,
        "mlx-community/gemma-3-4b-it-4bit": 3_439_894_985,
        "mlx-community/gemma-3-12b-it-4bit": 8_068_018_787,
        "mlx-community/Llama-4-Scout-17B-16E-Instruct-4bit": 61_143_654_248,
        "mlx-community/Llama-4-Maverick-17B-128E-Instruct-4bit": 225_923_469_800,
        LocalASRConfiguration.qwen3DefaultModel: 1_570_000_000,
        LocalASRConfiguration.mimoDefaultModel: 35_997_080_271,
    ]

    private static let downloadEstimateRegex = try! NSRegularExpression(
        pattern: #"([0-9]+(?:[\.,][0-9]+)?)\s*(TiB|GiB|MiB|KiB|TB|GB|MB|KB|T|G|M|K)(?![A-Za-z])"#,
        options: [.caseInsensitive]
    )

    private static func parseDownloadEstimateValue(_ rawValue: String) -> Double? {
        if rawValue.contains("."), rawValue.contains(",") {
            return Double(rawValue.replacingOccurrences(of: ",", with: ""))
        }
        if let commaIndex = rawValue.firstIndex(of: ",") {
            let fraction = rawValue[rawValue.index(after: commaIndex)...]
            let normalized = fraction.count == 3
                ? rawValue.replacingOccurrences(of: ",", with: "")
                : rawValue.replacingOccurrences(of: ",", with: ".")
            return Double(normalized)
        }
        return Double(rawValue)
    }

    private static func downloadEstimateMultiplier(for rawUnit: String) -> Double? {
        switch rawUnit {
        case "TIB": return pow(1024, 4)
        case "GIB": return pow(1024, 3)
        case "MIB": return pow(1024, 2)
        case "KIB": return 1024
        case "TB", "T": return 1_000_000_000_000
        case "GB", "G": return 1_000_000_000
        case "MB", "M": return 1_000_000
        case "KB", "K": return 1_000
        default: return nil
        }
    }
}
