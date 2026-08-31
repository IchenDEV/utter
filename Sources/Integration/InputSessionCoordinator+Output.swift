import Foundation

@MainActor
extension InputSessionCoordinator {
    func outputText(for raw: String, active: ActiveSession) async throws -> String {
        try await TextProcessor.withEspressoOutcomeTracking {
            try await trackedOutputText(for: raw, active: active)
        }
    }

    private func trackedOutputText(for raw: String, active: ActiveSession) async throws -> String {
        let options = TextProcessingOptions(settings: settings, inputLanguage: active.inputLanguage)
        let dictionarySnapshot = PersonalDictionary.shared.snapshot(settings: settings)
        let enableMemory = settings.enableMemory
        let memoryWindowMinutes = settings.memoryWindowMinutes
        let text: String
        let context: InputContext
        let formatKind: TextFormatKind?

        switch active.mode {
        case .direct:
            active.screenContextTask?.cancel()
            context = inputContext(for: active, screenContext: "", mode: .direct)
            text = textProcessor.basicClean(
                text: raw,
                inputLanguage: active.inputLanguage,
                dictionarySnapshot: dictionarySnapshot
            )
            formatKind = nil
        case .processed:
            let screenContext = await screenContext(from: active)
            context = inputContext(for: active, screenContext: screenContext.text, mode: .processed)
            let memoryContext = VoicePipelinePolicy.memoryContext(
                for: .processed,
                enableMemory: enableMemory,
                memoryWindowMinutes: memoryWindowMinutes,
                currentContext: context
            )
            let decision = TextFormatClassifier.classify(text: raw, context: context)
            formatKind = decision.kind
            text = await textProcessor.process(
                text: raw,
                options: options,
                screenContext: screenContext.text,
                screenImage: screenContext.image,
                memoryContext: memoryContext,
                inputContext: context,
                formatKind: decision.kind,
                dictionarySnapshot: dictionarySnapshot
            )
        case .command:
            let screenContext = await screenContext(from: active)
            context = inputContext(for: active, screenContext: screenContext.text, mode: .command)
            let memoryContext = VoicePipelinePolicy.memoryContext(
                for: .command,
                enableMemory: enableMemory,
                memoryWindowMinutes: memoryWindowMinutes,
                currentContext: context
            )
            formatKind = nil
            text = await textProcessor.processCommand(
                text: raw,
                options: options,
                screenContext: screenContext.text,
                screenImage: screenContext.image,
                memoryContext: memoryContext,
                inputContext: context,
                dictionarySnapshot: dictionarySnapshot
            )
        }

        let espressoOutcome = await textProcessor.consumeEspressoOutcome()
        if !Task.isCancelled, EspressoFallbackPolicy.selectMLXIfNeeded(
            after: espressoOutcome,
            settings: settings,
            expectedEspressoModelPath: options.espressoModelPath
        ) {
            Log.info("[InputSessionCoordinator] ANE-LM failed; selected MLX as the active backend")
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.info("[InputSessionCoordinator] refusing to complete session with empty output")
            if let espressoOutcome, espressoOutcome != .fallback {
                throw IntegrationError.operationFailedWithMessage(espressoOutcome.message)
            }
            throw IntegrationError.operationFailed
        }

        InputHistory.shared.addRecord(
            rawText: raw,
            processedText: text,
            wasProcessed: active.mode != .direct,
            context: context,
            formatKind: formatKind
        )
        return text
    }

    private func inputContext(
        for active: ActiveSession,
        screenContext: String,
        mode: OutputMode
    ) -> InputContext {
        InputContext(
            appName: active.client?.displayName,
            bundleIdentifier: active.client?.bundleIdentifier,
            screenContext: screenContext,
            outputMode: mode,
            inputLanguage: active.inputLanguage,
            source: .integration
        )
    }

    private func screenContext(from active: ActiveSession) async -> ScreenContextSnapshot {
        await active.screenContextTask?.value ?? .empty
    }
}
