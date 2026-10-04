import SwiftUI
import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
import UtterRuntime

@MainActor
extension PresentationPlugins {
    package static func general() -> PluginRegistration {
        contribution(id: "presentation.general", role: .settings, order: 10, label: "tab.general", symbol: "slider.horizontal.3",
            requires: platformRequirements) { context, _ in
                let platform = try platform(context)
                return { _ in AnyView(GeneralSettingsView().environmentObject(platform)) }
            }
    }
    package static func history() -> PluginRegistration {
        contribution(id: "presentation.history", role: .settings, order: 0, label: "tab.history", symbol: "chart.line.uptrend.xyaxis",
            requires: [DataServices.history.required]) { context, _ in
                let history = InputHistory(service: try context.require(DataServices.history))
                try context.scope.onDispose { history.dispose() }
                return { presentation in AnyView(HistoryStatsView(onCopy: presentation.copy).environmentObject(history)) }
            }
    }
    package static func models() -> PluginRegistration {
        contribution(id: "presentation.models", role: .settings, order: 20, label: "tab.models", symbol: "cpu",
            requires: [ModelServices.catalog.required, ModelServices.storage.required, ModelServices.lifecycle.required,
                       GenerationServices.connection.optional]) { context, _ in
                let catalog = ModelCatalogProjection(service: try context.require(ModelServices.catalog))
                let storage = try context.require(ModelServices.storage)
                let lifecycle = ModelLifecycleProjection(service: try context.require(ModelServices.lifecycle))
                let connection = try context.optional(GenerationServices.connection)
                try context.scope.onDispose { catalog.dispose(); lifecycle.dispose() }
                return { _ in AnyView(ModelManagementView(catalog: catalog, storage: storage, lifecycle: lifecycle,
                    remoteConnection: connection,
                    onUnloadWhisper: { Task { try? await lifecycle.unloadSpeech("speech.whisper") } },
                    onUnloadLLM: { Task { try? await lifecycle.unloadText() } },
                    onLoadLLM: { Task { try? await lifecycle.preloadText() } },
                    onBenchmarkLLM: { try await lifecycle.benchmark($0) },
                    onUnloadLocalASR: { Task { try? await lifecycle.unloadSpeech(nil) } })) }
            }
    }
    package static func style() -> PluginRegistration {
        contribution(id: "presentation.style", role: .settings, order: 30, label: "tab.style", symbol: "text.book.closed",
            requires: [DataServices.dictionary.required, DataServices.lexicons.required]) { context, _ in
                let lexicons = try context.require(DataServices.lexicons)
                let dictionary = PersonalDictionary(service: try context.require(DataServices.dictionary), lexicons: lexicons)
                return { _ in AnyView(DictionaryStyleView(lexicons: lexicons).environmentObject(dictionary)) }
            }
    }
    package static func integrations() -> PluginRegistration {
        contribution(id: "presentation.integrations", role: .settings, order: 40, label: "settings.integrations", symbol: "point.3.connected.trianglepath.dotted",
            requires: [IntegrationServices.clients.required]) { context, _ in
                let clients = try context.require(IntegrationServices.clients)
                return { _ in AnyView(IntegrationsSettingsView(registry: clients)) }
            }
    }
    package static func about() -> PluginRegistration {
        contribution(id: "presentation.about", role: .settings, order: 50, label: "tab.about", symbol: "info.circle",
            requires: platformRequirements) { context, _ in
                let platform = try platform(context)
                return { _ in AnyView(AboutView().environmentObject(platform)) }
            }
    }
    package static func onboarding() -> PluginRegistration {
        contribution(id: "presentation.onboarding", role: .onboarding,
            requires: platformRequirements + [ModelServices.catalog.required, ModelServices.storage.required]) { context, _ in
                let platform = try platform(context)
                let catalog = ModelCatalogProjection(service: try context.require(ModelServices.catalog))
                let storage = try context.require(ModelServices.storage)
                try context.scope.onDispose { catalog.dispose() }
                return { presentation in AnyView(OnboardingView(onComplete: presentation.completeOnboarding, catalog: catalog, storage: storage)
                    .environmentObject(platform)) }
            }
    }
}
