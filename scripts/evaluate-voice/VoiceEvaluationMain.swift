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
        try EvaluationAudio.validateModel(arguments, samples: samples)
        let host = try EvaluationRuntime(model: arguments.model, modelID: arguments.modelID, speech: arguments.speech)
        let report = try EvaluationReport(arguments: arguments, samples: samples)
        var completed = 0
        let started = ContinuousClock.now
        do {
            try report.manifest(state: "running", completed: 0)
            try await host.start()
            let audio = try EvaluationAudio(arguments: arguments, samples: samples, runtime: host.runtime)
            let speechFingerprint = try arguments.speech.map { try EvaluationReport.fingerprint($0.model) }
            for sample in samples {
                for attempt in 1...sample.repeatCount {
                    try Task.checkCancellation()
                    let remaining = Double(arguments.totalTimeout) - elapsedMilliseconds(since: started) / 1_000
                    guard remaining > 0 else { throw VoiceEvaluationError.timedOut }
                    guard try EvaluationReport.fingerprint(arguments.model) == report.assetFingerprint else {
                        throw GenerationServiceError.modelChanged
                    }
                    if let speech = arguments.speech {
                        guard try EvaluationReport.fingerprint(speech.model) == speechFingerprint else {
                            throw GenerationServiceError.modelChanged
                        }
                    }
                    let budget = EvaluationTokenBudget(limit: arguments.maxTokens)
                    await host.backend.setCandidate(sample.supplied_candidate, budget: budget)
                    let recipe = try await host.runtime.service(ModeServices.recipes).create(id: sample.recipeID, request: ())
                    let result = try await withOperationDeadline(for: .seconds(min(Double(arguments.caseTimeout), remaining))) { @MainActor in
                        if arguments.cold {
                            await host.backend.unload()
                            if let speech = arguments.speech {
                                try await host.runtime.service(SpeechServices.providers).reset(id: speech.providerID)
                            }
                        }
                        let baseRequest = try sample.request(model: arguments.model, modelID: arguments.modelID,
                            maxTokens: arguments.maxTokens, runtime: host.runtime)
                        let asrStarted = ContinuousClock.now
                        let transcript = try await audio.transcript(sample, request: baseRequest, runtime: host.runtime)
                        let asrTime = sample.audio_file == nil ? nil : elapsedMilliseconds(since: asrStarted)
                        let request = try sample.request(model: arguments.model, modelID: arguments.modelID,
                            maxTokens: arguments.maxTokens, runtime: host.runtime, transcript: transcript)
                        return EvaluationRunResult(transcript: transcript, asrMilliseconds: asrTime,
                            processing: try await recipe.process(request))
                    }
                    try report.write(sample, attempt: attempt, result: result.processing, transcript: result.transcript,
                        asrMilliseconds: result.asrMilliseconds, reservedTokens: await budget.reserved)
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

private struct EvaluationRunResult: Sendable {
    let transcript: String
    let asrMilliseconds: Double?
    let processing: ProcessingResult
}
