import Foundation

enum VoicePipelinePolicy {
    static func shouldCaptureScreenContext(outputMode: OutputMode, useScreenContext: Bool) -> Bool {
        switch outputMode {
        case .processed:
            return useScreenContext
        case .command:
            return true
        case .direct:
            return false
        }
    }

    static func shouldResolveEditCommandWithLLMFirst(outputMode: OutputMode) -> Bool {
        outputMode == .command
    }

    static func editCommand(from resolution: SpokenEditCommandLLMResolution?) -> SpokenEditCommand? {
        guard case .command(let command) = resolution else { return nil }
        return command
    }

    @MainActor
    static func memoryContext(
        for outputMode: OutputMode,
        settings: AppSettings,
        currentContext: InputContext? = nil,
        recentContextProvider: ((Int, InputContext?) -> String)? = nil
    ) -> String {
        memoryContext(
            for: outputMode,
            enableMemory: settings.enableMemory,
            memoryWindowMinutes: settings.memoryWindowMinutes,
            currentContext: currentContext,
            recentContextProvider: recentContextProvider
        )
    }

    @MainActor
    static func memoryContext(
        for outputMode: OutputMode,
        enableMemory: Bool,
        memoryWindowMinutes: Int,
        currentContext: InputContext? = nil,
        recentContextProvider: ((Int, InputContext?) -> String)? = nil
    ) -> String {
        guard enableMemory else { return "" }
        guard outputMode != .direct else { return "" }
        let provider = recentContextProvider ?? { MemoryStore.recentContext(windowMinutes: $0, currentContext: $1) }
        return provider(memoryWindowMinutes, currentContext)
    }
}
