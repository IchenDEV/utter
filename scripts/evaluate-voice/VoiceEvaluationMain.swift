import Foundation
import UtterContracts
import UtterEvaluation
import UtterMediaContracts
import UtterModels

@main
struct VoiceEvaluationMain {
    @MainActor
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Voice evaluation failed: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let arguments = try VoiceEvaluationArguments(Array(CommandLine.arguments.dropFirst()))
        let samples = try VoiceEvaluationCase.load(Data(contentsOf: arguments.corpus), maximumRuns: arguments.maximumRuns)
        guard ModelAssets.llmRepoIsComplete(at: arguments.model) else { throw GenerationServiceError.modelUnavailable }
        guard samples.allSatisfy({ $0.audio_file == nil }) else { throw VoiceEvaluationError.unavailableAudioProvider }
        let host = try EvaluationRuntime(model: arguments.model, modelID: arguments.modelID)
        let report = try EvaluationReport(arguments: arguments, expectedRuns: samples.reduce(0) { $0 + $1.repeatCount })
        var completed = 0
        let started = ContinuousClock.now
        do {
            try report.manifest(state: "running", completed: 0)
            try await host.start()
            for sample in samples {
                for attempt in 1...sample.repeatCount {
                    try Task.checkCancellation()
                    let remaining = Double(arguments.totalTimeout) - elapsedMilliseconds(since: started) / 1_000
                    guard remaining > 0 else { throw VoiceEvaluationError.timedOut }
                    guard try EvaluationReport.fingerprint(arguments.model) == report.assetFingerprint else {
                        throw GenerationServiceError.modelChanged
                    }
                    if arguments.cold { await host.backend.unload() }
                    await host.backend.setCandidate(sample.supplied_candidate)
                    let recipe = try await host.runtime.service(ModeServices.recipes).create(id: sample.recipeID, request: ())
                    let request = try sample.request(model: arguments.model, modelID: arguments.modelID,
                        maxTokens: arguments.maxTokens, runtime: host.runtime)
                    let result = try await withThrowingTaskGroup(of: ProcessingResult.self) { group in
                        group.addTask { @MainActor in try await recipe.process(request) }
                        group.addTask {
                            try await Task.sleep(for: .seconds(min(Double(arguments.caseTimeout), remaining)))
                            throw VoiceEvaluationError.timedOut
                        }
                        defer { group.cancelAll() }
                        return try await group.next()!
                    }
                    try report.write(sample, attempt: attempt, result: result)
                    completed += 1
                }
            }
            try await host.close()
            try report.manifest(state: "completed", completed: completed)
            try report.handle.close()
        } catch {
            try? await host.close()
            try? report.manifest(state: "partial", completed: completed, failure: String(reflecting: type(of: error)))
            try? report.handle.close()
            throw error
        }
    }
}
