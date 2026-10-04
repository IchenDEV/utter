import Foundation

package struct VoiceEvaluationArguments {
    package let corpus: URL
    package let model: URL
    package let modelID: String
    package let output: URL
    package let maximumRuns: Int
    package let caseTimeout: Int
    package let totalTimeout: Int
    package let maxTokens: Int
    package let cold: Bool

    package init(_ arguments: [String]) throws {
        var values: [String: String] = [:]
        var cold = false
        var index = 0
        let keys = ["--corpus", "--model", "--model-id", "--output", "--max-runs",
                    "--case-timeout", "--total-timeout", "--max-tokens"]
        while index < arguments.count {
            let key = arguments[index]
            if key == "--cold" {
                guard !cold else { throw VoiceEvaluationError.invalidArguments(key) }
                cold = true; index += 1; continue
            }
            guard keys.contains(key), values[key] == nil, index + 1 < arguments.count,
                  !arguments[index + 1].hasPrefix("--") else {
                throw VoiceEvaluationError.invalidArguments(key)
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        func required(_ key: String) throws -> String {
            guard let value = values[key], !value.isEmpty else {
                throw VoiceEvaluationError.invalidArguments("missing \(key)")
            }
            return value
        }
        func positive(_ key: String, defaultValue: Int, ceiling: Int) throws -> Int {
            let text = values[key] ?? String(defaultValue)
            guard let value = Int(text), value > 0, value <= ceiling else {
                throw VoiceEvaluationError.invalidArguments(key)
            }
            return value
        }
        corpus = URL(fileURLWithPath: try required("--corpus")).standardizedFileURL.resolvingSymlinksInPath()
        model = URL(fileURLWithPath: try required("--model")).standardizedFileURL.resolvingSymlinksInPath()
        modelID = try required("--model-id")
        output = URL(fileURLWithPath: try required("--output")).standardizedFileURL.resolvingSymlinksInPath()
        guard corpus != output, !output.path.hasPrefix(model.path + "/"), output != model else {
            throw VoiceEvaluationError.invalidArguments("output overlaps the corpus or model")
        }
        maximumRuns = try positive("--max-runs", defaultValue: 100, ceiling: 10_000)
        caseTimeout = try positive("--case-timeout", defaultValue: 120, ceiling: 3_600)
        totalTimeout = try positive("--total-timeout", defaultValue: 3_600, ceiling: 86_400)
        maxTokens = try positive("--max-tokens", defaultValue: 4_096, ceiling: 4_096)
        self.cold = cold
    }
}
