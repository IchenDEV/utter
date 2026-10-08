import CryptoKit
import Foundation
import UtterContracts
import UtterEvaluation
import UtterMediaContracts

struct EvaluationReport {
    let arguments: VoiceEvaluationArguments
    let assetFingerprint: String
    let expectedRuns: Int
    let expectedCaseRuns: [String: Int]
    let speechAssetFingerprint: String?
    let handle: FileHandle
    let manifestURL: URL

    init(arguments: VoiceEvaluationArguments, samples: [VoiceEvaluationCase]) throws {
        self.arguments = arguments
        expectedRuns = samples.reduce(0) { $0 + $1.repeatCount }
        expectedCaseRuns = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0.repeatCount) })
        speechAssetFingerprint = try arguments.speech.map { try Self.fingerprint($0.model) }
        assetFingerprint = try Self.fingerprint(arguments.model)
        manifestURL = arguments.output.appendingPathExtension("manifest.json")
        guard !FileManager.default.fileExists(atPath: arguments.output.path),
              !FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw VoiceEvaluationError.invalidArguments("output already exists")
        }
        try Data().write(to: arguments.output, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: arguments.output)
    }

    func write(_ sample: VoiceEvaluationCase, attempt: Int, result: ProcessingResult, transcript: String,
               asrMilliseconds: Double?, reservedTokens: Int) throws {
        var object: [String: Any] = ["id": "\(sample.id)-\(attempt)", "case_id": sample.id,
            "language": sample.language, "faithful_reference": sample.faithful_reference,
            "asr_text": transcript, "processed_text": result.text,
            "processing_latency_ms": result.trace?.elapsedMilliseconds ?? 0,
            "outcome": result.decision.disposition.rawValue,
            "evaluation_path": sample.supplied_candidate == nil ? "generation" : "fixed_candidate"]
        object["cold"] = arguments.cold
        object["generation_timings"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.timings))
        object["reserved_output_tokens"] = reservedTokens
        if let asrMilliseconds { object["asr_latency_ms"] = asrMilliseconds }
        if let reference = sample.sendable_reference { object["sendable_reference"] = reference }
        object["terms"] = sample.terms ?? []
        if let reason = result.decision.reason { object["fallback_reason"] = reason }
        if let trace = result.trace {
            object["trace"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(trace))
        }
        let constraintsPass = (sample.terms ?? []).allSatisfy { result.text.contains($0) }
            && !(sample.forbidden_terms ?? []).contains { result.text.contains($0) }
            && (sample.expected_outcome == nil || sample.expected_outcome == result.decision.disposition.rawValue)
        object["constraints_pass"] = constraintsPass
        object["expected_outcome"] = sample.expected_outcome
        object["forbidden_terms"] = sample.forbidden_terms ?? []
        object["semantic_review"] = "required"
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(10)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    func manifest(state: String, completed: Int, failure: String? = nil) throws {
        var object: [String: Any] = ["state": state, "completed_runs": completed,
            "expected_runs": expectedRuns, "expected_cases": expectedCaseRuns, "model_id": arguments.modelID,
            "model_asset_fingerprint": assetFingerprint, "cold": arguments.cold,
            "max_tokens": arguments.maxTokens, "case_timeout_seconds": arguments.caseTimeout,
            "total_timeout_seconds": arguments.totalTimeout,
            "source_commit": ProcessInfo.processInfo.environment["UTTER_EVAL_REVISION"] ?? "unknown",
            "quality_status": "requires semantic review"]
        if let speech = arguments.speech {
            object["speech_provider"] = speech.providerID
            object["speech_model_id"] = speech.modelID
            object["speech_asset_fingerprint"] = speechAssetFingerprint
        }
        if let failure { object["failure"] = failure }
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifestURL, options: .atomic)
    }

    static func fingerprint(_ directory: URL) throws -> String {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]) else { throw CocoaError(.fileReadUnknown) }
        var records: [String] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            var record = file.path.replacingOccurrences(of: directory.path + "/", with: "")
                + ":\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            if file.pathExtension == "json" {
                record += ":" + SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
            }
            records.append(record)
        }
        return SHA256.hash(data: Data(records.sorted().joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
