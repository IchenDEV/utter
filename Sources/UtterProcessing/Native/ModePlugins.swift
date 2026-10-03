import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
package enum ModePlugins {
    package static func recipes() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "modes.recipes", provides: [ModeServices.recipes.reference])) { context, _ in
            let registry = ProviderRegistry<Void, any ModeRecipeService>()
            try context.scope.onRevoke { registry.close() }
            try context.provide(ModeServices.recipes, value: registry)
        }
    }

    package static func direct() -> PluginRegistration {
        recipe(ModeServices.direct, title: L("mode.verbatim"), alias: OutputMode.direct.rawValue) { _ in .direct }
    }
    package static func formatting() -> PluginRegistration {
        recipe(ModeServices.formatting, title: L("mode.smart_format"), alias: OutputMode.processed.rawValue) { _ in .formatting }
    }
    package static func command() -> PluginRegistration {
        recipe(ModeServices.command, title: L("mode.voice_command"), alias: OutputMode.command.rawValue) { _ in .command }
    }
    package static func translation() -> PluginRegistration {
        recipe(ModeServices.translation, title: L("settings.translation")) { mode in
            guard case .translation = mode else { throw GenerationServiceError.unsupportedOperation }
            return mode
        }
    }
    package static func edit() -> PluginRegistration {
        recipe(ModeServices.edit, title: L("mode.selection_edit")) { mode in
            guard case .selectionEdit = mode else { throw GenerationServiceError.unsupportedOperation }
            return mode
        }
    }

    private static func recipe(_ key: ServiceKey<ProviderDescriptor>, title: String, alias: String? = nil,
                               mode: @escaping (TextProcessingMode) throws -> TextProcessingMode) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: key.name, requires: [ModeServices.recipes.required, ProcessingServices.text.required], provides: [key.reference]
        )) { context, _ in
            let registry = try context.require(ModeServices.recipes)
            let service = BuiltinModeRecipe(processor: try context.require(ProcessingServices.text), mode: mode, isCurrent: { context.isReady })
            let descriptor = ProviderDescriptor(id: key.name, legacyIDs: alias.map { [$0] } ?? [], displayName: title)
            try registry.register(ProviderDefinition(descriptor: descriptor) { _ in service }, scope: context.scope)
            try context.provide(key, value: descriptor)
        }
    }
}

@MainActor
private final class BuiltinModeRecipe: ModeRecipeService {
    private let processor: any ProcessingService
    private let isCurrent: () -> Bool
    private let mode: (TextProcessingMode) throws -> TextProcessingMode
    init(processor: any ProcessingService, mode: @escaping (TextProcessingMode) throws -> TextProcessingMode,
         isCurrent: @escaping () -> Bool) {
        self.processor = processor
        self.mode = mode
        self.isCurrent = isCurrent
    }
    func process(_ request: ProcessingRequest) async throws -> ProcessingResult {
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        let result = try await processor.process(request.withMode(mode(request.mode)))
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        return result
    }
}
