import SwiftUI

enum FormattingModelType: String, CaseIterable {
    case qwen
    case gemma
    case llama
    case espresso
    case remote
    case custom

    var family: ModelCatalog.ModelFamily? {
        switch self {
        case .qwen: .qwen
        case .gemma: .gemma
        case .llama: .llama
        case .espresso, .remote, .custom: nil
        }
    }

    var isRecommended: Bool { self == .qwen }

    var title: String {
        switch self {
        case .qwen:
            "\(ModelCatalog.ModelFamily.qwen.rawValue) · \(L("common.recommended_short"))"
        case .gemma: ModelCatalog.ModelFamily.gemma.rawValue
        case .llama: ModelCatalog.ModelFamily.llama.rawValue
        case .espresso: "ANE"
        case .remote: L("model.family.remote")
        case .custom: L("common.custom")
        }
    }

    static func resolvedLocalSelection(
        pending: FormattingModelType?,
        activeFamily: ModelCatalog.ModelFamily??
    ) -> FormattingModelType {
        if let pending { return pending }
        guard let activeFamily else { return .qwen }
        switch activeFamily {
        case .qwen: return .qwen
        case .gemma: return .gemma
        case .llama: return .llama
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

    func selectLocalFamily(_ family: ModelCatalog.ModelFamily) {
        selectedModelFamily = family
        if settings.localLLMBackend != .mlx {
            switch family {
            case .qwen: pendingFormattingTypeAfterBackendChange = .qwen
            case .gemma: pendingFormattingTypeAfterBackendChange = .gemma
            case .llama: pendingFormattingTypeAfterBackendChange = .llama
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
