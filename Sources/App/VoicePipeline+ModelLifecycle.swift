import Foundation

@MainActor
extension VoicePipeline {
    func unloadLLM() {
        formattingPreloadGeneration += 1
        processingTask?.cancel()
        processingTask = nil
        replacementTask?.cancel()
        replacementTask = nil
        appState.clearPendingReplacement()
        if appState.phase == .processing {
            appState.phase = .idle
            appState.statusMessage = L("status.ready")
        } else if appState.statusMessage == L("pipeline.loading_llm") {
            appState.statusMessage = L("status.ready")
        }
        appState.llmModelReady = false

        let precedingTask = formattingModelLifecycleTask
        formattingModelLifecycleTask = Task { @MainActor [weak self] in
            _ = await precedingTask?.value
            guard let self else { return nil }
            await self.textProcessor.unloadLLM()
            return nil
        }
    }

    func loadLLM() {
        enqueueFormattingModelPreload(showFailureInStatus: true)
    }

    @discardableResult
    func enqueueFormattingModelPreload(
        showFailureInStatus: Bool
    ) -> Task<EspressoGenerationOutcome?, Never> {
        let precedingTask = formattingModelLifecycleTask
        let task: Task<EspressoGenerationOutcome?, Never> = Task { @MainActor [weak self] in
            _ = await precedingTask?.value
            guard let self else { return nil }
            return await self.preloadFormattingModelNow(
                showFailureInStatus: showFailureInStatus
            )
        }
        formattingModelLifecycleTask = task
        return task
    }
}
