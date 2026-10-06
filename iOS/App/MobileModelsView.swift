import SwiftUI
import UtterMobile

@MainActor
struct MobileModelsView: View {
    @ObservedObject var controller: MobileController
    @State private var deleting: MobileModel?
    var body: some View {
        Form {
            Section {
                Text(L("ios.models.local_notice"))
                if let error = controller.libraryError {
                    Text(L(error)).foregroundStyle(.red)
                    Button(L("ios.action.retry")) { Task { await controller.prepareLibrary() } }
                }
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Speech").font(.headline)
                        Text(L("ios.models.apple_detail")).font(.subheadline)
                    }
                    Spacer()
                    if controller.selectedModel == "apple" { Image(systemName: "checkmark").accessibilityLabel(L("ios.models.selected")) }
                }
                if controller.applePreparing {
                    ProgressView(L("ios.models.preparing"))
                    Button(L("ios.action.cancel")) { controller.cancelApplePreparation() }
                }
                else if controller.appleReady {
                    Text(L("ios.models.ready")).foregroundStyle(.primary).accessibilityIdentifier("model.apple.download")
                } else {
                    Button(L("ios.models.prepare")) { Task { await controller.prepareAppleModel() } }
                        .disabled(!controller.canChangeConfiguration).accessibilityIdentifier("model.apple.download")
                }
                if controller.selectedModel != "apple" {
                    Button(L("ios.models.use")) { Task { await controller.selectModel("apple") } }.disabled(!controller.canChangeConfiguration).accessibilityIdentifier("model.use.apple")
                }
            } header: { mobileSectionHeader("ios.models.system") }
            Section {
                ForEach(controller.models.filter { !$0.experimental }) { model in modelRow(model) }
            } header: { mobileSectionHeader("ios.models.compact") }
            Section {
                ForEach(controller.models.filter(\.experimental)) { model in modelRow(model) }
            } header: { mobileSectionHeader("ios.models.advanced") } footer: { mobileSectionFooter("ios.models.experimental_notice") }
        }.navigationTitle(L("ios.tab.models")).navigationBarTitleDisplayMode(.inline)
            
            .confirmationDialog(L("ios.models.delete_title"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(L("ios.action.delete"), role: .destructive) {
                    if let model = deleting { Task { await controller.deleteModel(model.id) } }; deleting = nil
                }.accessibilityIdentifier("model.delete.confirm")
            } message: { Text(deleting?.name ?? "") }
    }
    private func modelRow(_ model: MobileModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.name).font(.headline)
                Spacer()
                if controller.selectedModel == model.id { Image(systemName: "checkmark").accessibilityLabel(L("ios.models.selected")) }
            }
            if model.bytes > 0 { Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)).font(.subheadline).monospacedDigit() }
            if model.downloading {
                ProgressView(value: min(1, max(0, model.progress)))
                Text(L("ios.models.downloading") + " · " + model.progress.formatted(.percent.precision(.fractionLength(0)))).font(.footnote).monospacedDigit()
                Button(L("ios.action.cancel")) { controller.cancelDownload(model.id) }.accessibilityIdentifier("model.cancel.\(model.id)")
            } else {
                if let error = model.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("model.error.\(model.id)")
                }
                HStack {
                    if model.downloaded {
                        Button(L(controller.selectedModel == model.id ? "ios.models.selected" : "ios.models.use")) { Task { await controller.selectModel(model.id) } }
                            .disabled(controller.selectedModel == model.id || !controller.canChangeConfiguration)
                            .accessibilityIdentifier("model.use.\(model.id)")
                        Spacer()
                        Button(L("ios.action.delete"), role: .destructive) { deleting = model }.disabled(!controller.canChangeConfiguration)
                            .accessibilityIdentifier("model.delete.\(model.id)")
                    } else {
                        Button(L(model.error == nil ? "ios.models.download" : "ios.action.retry")) { Task { await controller.downloadModel(model.id) } }
                            .accessibilityIdentifier("model.download.\(model.id)")
                    }
                }.buttonStyle(.borderless)
            }
        }.padding(.vertical, 6)
    }
}
