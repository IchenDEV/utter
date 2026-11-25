import UtterPresentationContracts
import UtterContracts
import SwiftUI

enum FormattingModelType: String, CaseIterable {
    case qwen
    case gemma
    case llama
    case edge0
    case espresso
    case remote
    case custom

    var family: ModelCatalogProjection.ModelFamily? {
        switch self {
        case .qwen: .qwen
        case .gemma: .gemma
        case .llama: .llama
        case .edge0: .edge0
        case .espresso, .remote, .custom: nil
        }
    }

    var isRecommended: Bool { self == .qwen }

    var title: String {
        switch self {
        case .qwen:
            "\(ModelCatalogProjection.ModelFamily.qwen.rawValue) · \(L("common.recommended_short"))"
        case .gemma: ModelCatalogProjection.ModelFamily.gemma.rawValue
        case .llama: ModelCatalogProjection.ModelFamily.llama.rawValue
        case .edge0: ModelCatalogProjection.ModelFamily.edge0.rawValue
        case .espresso: "ANE"
        case .remote: L("model.family.remote")
        case .custom: L("common.custom")
        }
    }

    static func resolvedLocalSelection(
        pending: FormattingModelType?,
        activeFamily: ModelCatalogProjection.ModelFamily??
    ) -> FormattingModelType {
        if let pending { return pending }
        guard let activeFamily else { return .qwen }
        switch activeFamily {
        case .qwen: return .qwen
        case .gemma: return .gemma
        case .llama: return .llama
        case .edge0: return .edge0
        case nil: return .custom
        }
    }
}

extension ModelManagementView {
    var familyPicker: some View {
        Picker(L("model.family.title"), selection: familySelection) {
            ForEach(FormattingModelType.allCases, id: \.self) { type in
                Text(type.title)
                    .tag(type)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var familySelection: Binding<FormattingModelType> {
        Binding(
            get: {
                if settings.useRemoteLLM { return .remote }
                if settings.localLLMBackend == .espresso { return .espresso }
                switch selectedModelFamily {
                case .qwen: return .qwen
                case .gemma: return .gemma
                case .llama: return .llama
                case .edge0: return .edge0
                case nil: return .custom
                }
            },
            set: { selection in
                switch selection {
                case .qwen:
                    selectLocalFamily(.qwen)
                case .gemma:
                    selectLocalFamily(.gemma)
                case .llama:
                    selectLocalFamily(.llama)
                case .edge0:
                    selectLocalFamily(.edge0)
                case .espresso:
                    selectEspressoLLM()
                case .remote:
                    selectRemoteLLM()
                case .custom:
                    selectCustomLLM()
                }
            }
        )
    }

    func selectLocalFamily(_ family: ModelCatalogProjection.ModelFamily) {
        selectedModelFamily = family
        if family == .edge0 {
            // Edge0 is download-only in this build; selecting the family must
            // not switch the active text model or unload the current one.
            return
        }
        if settings.localLLMBackend != .mlx {
            switch family {
            case .qwen: pendingFormattingTypeAfterBackendChange = .qwen
            case .gemma: pendingFormattingTypeAfterBackendChange = .gemma
            case .llama: pendingFormattingTypeAfterBackendChange = .llama
            case .edge0: pendingFormattingTypeAfterBackendChange = .edge0
            }
        }
        let changedBackend = settings.useRemoteLLM || settings.localLLMBackend != .mlx
        if changedBackend {
            onUnloadLLM?()
            settings.useRemoteLLM = false
            settings.localLLMBackend = .mlx
        }
        if changedBackend,
           catalog.llmModels.first(where: { $0.id == settings.llmModel })?.family == family {
            onLoadLLM?()
        }
    }

    func selectEspressoLLM() {
        guard settings.useRemoteLLM || settings.localLLMBackend != .espresso else { return }
        onUnloadLLM?()
        settings.useRemoteLLM = false
        settings.localLLMBackend = .espresso
        if !settings.espressoModelPath.isEmpty {
            onLoadLLM?()
        }
    }

    func selectRemoteLLM() {
        if !settings.useRemoteLLM {
            onUnloadLLM?()
            settings.useRemoteLLM = true
        }
    }

    func selectCustomLLM() {
        selectedModelFamily = nil
        if settings.localLLMBackend != .mlx {
            pendingFormattingTypeAfterBackendChange = .custom
        }
        let changedBackend = settings.useRemoteLLM || settings.localLLMBackend != .mlx
        if changedBackend {
            onUnloadLLM?()
            settings.useRemoteLLM = false
            settings.localLLMBackend = .mlx
        }
        if changedBackend,
           catalog.llmModels.first(where: { $0.id == settings.llmModel })?.family == nil {
            onLoadLLM?()
        }
    }
}
