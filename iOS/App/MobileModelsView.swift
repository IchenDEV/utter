import SwiftUI
import UtterMobile

/// Speech and rewrite models, with the same catalog as the desktop app. Downloaded rows are choices (checkmark);
/// the cloud on the other rows downloads them. Models this device cannot hold say why instead of failing later.
@MainActor
struct MobileModelsView: View {
    @ObservedObject var controller: MobileController
    @State private var deleting: MobileModel?
    @State private var showsLegacy = false

    var body: some View {
        List {
            if let error = controller.libraryError {
                Section {
                    Text(L(error)).foregroundStyle(.red)
                    Button(L("ios.action.retry")) { Task { await controller.prepareLibrary() } }
                }
            }
            speechSections
            polishSection
            Section { Text(storageText).font(.footnote).foregroundStyle(.secondary) } footer: { Text(L("ios.models.local_notice")) }
        }
        .navigationTitle(L("ios.tab.models")).navigationBarTitleDisplayMode(.large)
        .confirmationDialog(L("ios.models.delete_title"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(L("ios.action.delete"), role: .destructive) {
                if let model = deleting { Task { await controller.deleteModel(model.id) } }; deleting = nil
            }.accessibilityIdentifier("model.delete.confirm")
        } message: { Text(deleting?.name ?? "") }
    }

    // MARK: Speech recognition

    @ViewBuilder private var speechSections: some View {
        Section {
            appleRow
            ForEach(ordered(controller.models.filter { $0.kind == .speech && $0.isWhisper })) { row($0) }
        } header: { mobileSectionHeader("ios.models.speech") } footer: { mobileSectionFooter("ios.models.speech_footer") }
        Section {
            ForEach(ordered(controller.models.filter { $0.kind == .speech && !$0.isWhisper })) { row($0) }
        } header: { mobileSectionHeader("ios.models.more_speech") } footer: { mobileSectionFooter("ios.models.experimental_notice") }
    }

    private var appleRow: some View {
        let selected = controller.selectedModel == "apple"
        return Group {
            if controller.appleReady {
                Button { Task { await controller.selectModel("apple") } } label: {
                    appleLabel { if selected { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.blue) } }
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("model.use.apple")
            } else {
                appleLabel {
                    if controller.applePreparing {
                        Button { controller.cancelApplePreparation() } label: { ProgressRing(progress: 0) }.buttonStyle(.borderless)
                            .accessibilityLabel(L("ios.action.cancel"))
                    } else {
                        Button { Task { await controller.prepareAppleModel() } } label: { Image(systemName: "icloud.and.arrow.down").font(.title3) }
                            .buttonStyle(.borderless).tint(.blue).accessibilityLabel(L("ios.models.prepare"))
                            .accessibilityIdentifier("model.apple.download")
                    }
                }
            }
        }
    }

    private func appleLabel<Accessory: View>(@ViewBuilder _ accessory: () -> Accessory) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("ios.models.system")).font(.body)
                Text(controller.applePreparing ? L("ios.models.preparing") : L("ios.models.apple_detail")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            accessory()
        }.contentShape(Rectangle()).padding(.vertical, 2)
    }

    // MARK: Rewrite

    @ViewBuilder private var polishSection: some View {
        let all = ordered(controller.models.filter { $0.kind == .polish })
        Section {
            systemPolishRow
            ForEach(all.filter { $0.tier != .legacy }) { row($0) }
            if all.contains(where: { $0.tier == .legacy }) {
                DisclosureGroup(L("ios.models.legacy"), isExpanded: $showsLegacy) {
                    ForEach(all.filter { $0.tier == .legacy }) { row($0) }
                }.accessibilityIdentifier("models.legacy")
            }
        } header: { mobileSectionHeader("ios.models.polish") } footer: { mobileSectionFooter("ios.models.polish_footer") }
    }

    private var systemPolishRow: some View {
        let available = controller.systemPolishAvailable
        let selected = controller.polishModel == "system"
        let label = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("ios.models.system_polish")).font(.body).foregroundStyle(available ? .primary : .secondary)
                Text(L(available ? "ios.models.system_polish_detail" : "ios.settings.polish_unavailable")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if selected && available { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.blue) }
        }.contentShape(Rectangle()).padding(.vertical, 2)
        return Group {
            if available {
                Button { Task { await controller.selectModel("system") } } label: { label }.buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("model.use.system")
            } else { label }
        }
    }

    // MARK: Rows

    private func row(_ model: MobileModel) -> some View {
        let selected = model.kind == .speech ? controller.selectedModel == model.id : controller.polishModel == model.id
        return MobileModelRow(model: model, selected: selected,
                              select: { Task { await controller.selectModel(model.id) } },
                              download: { Task { await controller.downloadModel(model.id) } },
                              cancel: { controller.cancelDownload(model.id) })
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.downloaded {
                Button(role: .destructive) { deleting = model } label: { Label(L("ios.action.delete"), systemImage: "trash") }
                    .accessibilityIdentifier("model.delete.\(model.id)")
            }
        }
        .contextMenu {
            if model.downloaded { Button(role: .destructive) { deleting = model } label: { Label(L("ios.action.delete"), systemImage: "trash") } }
        }
    }

    /// Recommended first, models this device cannot hold last; otherwise the desktop order.
    private func ordered(_ rows: [MobileModel]) -> [MobileModel] {
        rows.enumerated().sorted { a, b in
            let (x, y) = (rank(a.element), rank(b.element))
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
    }

    private func rank(_ model: MobileModel) -> Int {
        if case .blocked = model.fit { return 10 + model.tier.rawValue }
        return model.tier.rawValue
    }

    private var storageText: String {
        let used = controller.models.filter(\.downloaded).reduce(Int64(0)) { $0 + $1.bytes }
        return String(format: L("ios.models.storage"), ByteCountFormatter.string(fromByteCount: used, countStyle: .file))
    }
}
