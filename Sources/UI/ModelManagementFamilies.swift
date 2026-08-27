import SwiftUI

extension ModelManagementView {
    var familyPicker: some View {
        HStack(spacing: 0) {
            ForEach(ModelCatalog.ModelFamily.allCases, id: \.self) { family in
                familyButton(family)
            }
            espressoFamilyButton
            remoteFamilyButton
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    func familyButton(_ family: ModelCatalog.ModelFamily) -> some View {
        let isSelected = !settings.useRemoteLLM
            && settings.localLLMBackend == .mlx
            && selectedModelFamily == family

        return Button(action: { selectLocalFamily(family) }) {
            VStack(spacing: 2) {
                Image(systemName: family.icon)
                    .font(.system(size: 14))
                Text(family.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .foregroundStyle(
            isSelected
                ? Color.accentColor
                : Color.primary
        )
    }

    var espressoFamilyButton: some View {
        let isSelected = !settings.useRemoteLLM && settings.localLLMBackend == .espresso
        return Button(action: selectEspressoLLM) {
            VStack(spacing: 2) {
                Image(systemName: "neural.engine")
                    .font(.system(size: 14))
                Text("ANE")
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }

    var remoteFamilyButton: some View {
        Button(action: selectRemoteLLM) {
            VStack(spacing: 2) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 14))
                Text(L("model.family.remote"))
                    .font(.system(size: 10, weight: settings.useRemoteLLM ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            settings.useRemoteLLM
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .foregroundStyle(
            settings.useRemoteLLM
                ? Color.accentColor
                : Color.primary
        )
    }

    func selectLocalFamily(_ family: ModelCatalog.ModelFamily) {
        selectedModelFamily = family
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
}
