import Foundation
import UtterContracts
import UtterMediaContracts

@MainActor
final class ScopedProcessingService: ProcessingService {
    private struct Operation {
        let cancel: () -> Void
        let drain: () async -> Void
    }

    private let processor: TextProcessor
    private let isCurrent: () -> Bool
    private var operations: [UUID: Operation] = [:]
    private var closed = false

    init(processor: TextProcessor, isCurrent: @escaping () -> Bool) {
        self.processor = processor
        self.isCurrent = isCurrent
    }

    func process(_ request: ProcessingRequest) async throws -> ProcessingResult {
        try await run {
            try self.requireFrozenModel(request)
            let observation = ProcessingObservation(collectsBody: request.collectsDiagnostics)
            return try await ProcessingObservations.$current.withValue(observation) {
              try await TextProcessor.withEspressoOutcomeTracking {
                let text = await self.output(request)
                try Task.checkCancellation()
                let outcome = await self.processor.consumeEspressoOutcome()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ProcessingError.emptyResult(outcome)
                }
                observation.complete(source: request.text, candidate: text)
                let snapshot = observation.snapshot()
                return ProcessingResult(text: text, generationOutcome: outcome,
                    decision: snapshot.decision, trace: snapshot.trace, timings: snapshot.timings)
              }
            }
        }
    }

    private func requireFrozenModel(_ request: ProcessingRequest) throws {
        guard request.mode != .direct, !request.options.useRemoteLLM,
              case .frozen(let bundle, let directory) = request.options.modelLocations else { return }
        if request.options.localLLMBackend == .espresso {
            guard bundle != nil || (request.options.fallbackToMLXOnEspressoFailure && directory != nil) else {
                throw GenerationServiceError.modelUnavailable
            }
        } else if directory == nil { throw GenerationServiceError.modelUnavailable }
    }

    func cleanReplacement(_ text: String, language: InputLanguage) throws -> String {
        guard !closed, isCurrent(), !Task.isCancelled else { throw CancellationError() }
        return processor.cleanCommandGeneratedOutput(text, inputLanguage: language)
    }

    func resolveEditCommand(
        text: String, options: TextProcessingOptions, dictionary: PersonalDictionarySnapshot,
        context: SpokenEditCommandResolutionContext
    ) async throws -> SpokenEditCommandLLMResolution? {
        try await run {
            await self.processor.resolveSpokenEditCommandResolution(
                text: text, options: options, context: context, dictionarySnapshot: dictionary
            )
        }
    }

    func revoke() {
        closed = true
        for operation in operations.values { operation.cancel() }
    }

    func close() async {
        revoke()
        let pending = Array(operations.values)
        for operation in pending { await operation.drain() }
    }

    private func run<Value>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try checkCurrent()
        let id = UUID()
        let task = Task { @MainActor in
            try self.checkCurrent()
            return try await operation()
        }
        operations[id] = Operation(cancel: { task.cancel() }, drain: { _ = await task.result })
        defer { operations[id] = nil }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try checkCurrent()
            return result
        } onCancel: {
            task.cancel()
        }
    }

    private func checkCurrent() throws {
        try Task.checkCancellation()
        guard !closed, isCurrent() else { throw CancellationError() }
    }

    private func output(_ request: ProcessingRequest) async -> String {
        switch request.mode {
        case .direct:
            let text = processor.basicClean(
                text: request.text, inputLanguage: request.options.inputLanguage,
                dictionarySnapshot: request.dictionary
            )
            ProcessingObservations.current?.record(source: request.text, candidate: text,
                decision: ProcessingDecision(.direct))
            return text
        case .formatting:
            return await processor.process(
                text: request.text, options: request.options, screenContext: request.screenContext,
                screenImage: request.screenImage, memoryContext: request.memoryContext,
                inputContext: request.inputContext, formatKind: request.formatKind,
                allowsPreparedFallback: request.allowsPreparedFallback,
                dictionarySnapshot: request.dictionary
            )
        case .command:
            return await processor.processCommand(
                text: request.text, options: request.options, screenContext: request.screenContext,
                screenImage: request.screenImage, memoryContext: request.memoryContext,
                inputContext: request.inputContext, dictionarySnapshot: request.dictionary
            )
        case .translation(let language):
            return await processor.translate(
                text: request.text, targetLanguage: language, options: request.options,
                dictionarySnapshot: request.dictionary
            )
        case .selectionEdit(let intent, let command):
            return await processor.processSelectionEdit(
                selectedText: request.text, intent: intent, options: request.options,
                spokenCommand: command, memoryContext: request.memoryContext,
                inputContext: request.inputContext, dictionarySnapshot: request.dictionary
            )
        }
    }
}
