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
            try await TextProcessor.withEspressoOutcomeTracking {
                let text = await self.output(request)
                try Task.checkCancellation()
                let outcome = await self.processor.consumeEspressoOutcome()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ProcessingError.emptyResult(outcome)
                }
                return ProcessingResult(text: text, generationOutcome: outcome)
            }
        }
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

    func close() async {
        closed = true
        let pending = Array(operations.values)
        for operation in pending { operation.cancel() }
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
            return processor.basicClean(
                text: request.text, inputLanguage: request.options.inputLanguage,
                dictionarySnapshot: request.dictionary
            )
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
