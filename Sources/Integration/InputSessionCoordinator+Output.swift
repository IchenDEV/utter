import Foundation

@MainActor
extension InputSessionCoordinator {
    func outputText(for raw: String, active: ActiveSession) async throws -> String {
        let options = TextProcessingOptions(settings: settings, inputLanguage: active.inputLanguage)
        let dictionarySnapshot = PersonalDictionary.shared.snapshot()
        let enableMemory = settings.enableMemory
        let memoryWindowMinutes = settings.memoryWindowMinutes
        let text: String
        let context: InputContext

        switch active.mode {
        case .direct:
            active.screenContextTask?.cancel()
            context = inputContext(for: active, screenContext: "", mode: .direct)
            text = textProcessor.basicClean(
                text: raw,
                inputLanguage: active.inputLanguage,
                dictionarySnapshot: dictionarySnapshot
            )
        case .processed:
            let screenContext = await screenContext(from: active)
            context = inputContext(for: active, screenContext: screenContext.text, mode: .processed)
            let memoryContext = VoicePipelinePolicy.memoryContext(
                for: .processed,
                enableMemory: enableMemory,
                memoryWindowMinutes: memoryWindowMinutes,
                currentContext: context
            )
            text = await textProcessor.process(
                text: raw,
                options: options,
                screenContext: screenContext.text,
                screenImage: screenContext.image,
                memoryContext: memoryContext,
                inputContext: context,
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

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.info("[InputSessionCoordinator] refusing to complete session with empty output")
            throw IntegrationError.operationFailed
        }

        InputHistory.shared.addRecord(
            rawText: raw,
            processedText: text,
            wasProcessed: active.mode != .direct,
            context: context
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
