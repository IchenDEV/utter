import SwiftUI

enum FormattingModelType: String, CaseIterable {
    case qwen
    case gemma
    case llama
    case remote
    case custom

    var family: ModelCatalog.ModelFamily? {
        switch self {
        case .qwen: .qwen
        case .gemma: .gemma
        case .llama: .llama
        case .remote, .custom: nil
        }
    }

    var isRecommended: Bool { self == .qwen }

    var title: String {
        switch self {
        case .qwen:
            "\(ModelCatalog.ModelFamily.qwen.rawValue) · \(L("common.recommended_short"))"
        case .gemma: ModelCatalog.ModelFamily.gemma.rawValue
        case .llama: ModelCatalog.ModelFamily.llama.rawValue
        case .remote: L("model.family.remote")
        case .custom: L("common.custom")
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
                if settings.useRemoteLLM {
                    return .remote
                }
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
        if settings.useRemoteLLM {
            settings.useRemoteLLM = false
            if catalog.llmModels.first(where: { $0.id == settings.llmModel })?.family == family {
                onLoadLLM?()
            }
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
        if settings.useRemoteLLM {
            settings.useRemoteLLM = false
            if let activeModel = catalog.llmModels.first(where: { $0.id == settings.llmModel }),
               activeModel.family == nil {
                onLoadLLM?()
            }
        }
    }
}
