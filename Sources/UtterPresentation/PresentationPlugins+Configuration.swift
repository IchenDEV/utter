import SwiftUI
import UtterContracts
import UtterPresentationContracts
import UtterRuntime

@MainActor
extension PresentationPlugins {
    package static func configuration() -> PluginRegistration {
        contribution(id: "presentation.configuration", role: .settings, order: 60,
            label: "plugins.title", symbol: "puzzlepiece.extension",
            requires: [DataServices.configuration.required]) { context, _ in
                let service = try context.require(DataServices.configuration)
                return { _ in AnyView(PluginConfigurationView(service: service, isCurrent: { context.isCurrent })) }
            }
    }
}

@MainActor
private struct PluginConfigurationView: View {
    let service: any ConfigurationService
    let isCurrent: () -> Bool
    @State private var text = ""
    @State private var message = ""
    @State private var failed = false
    var body: some View {
        Form {
            Section(L("plugins.title")) {
                Text(L("plugins.description")).foregroundStyle(.secondary)
                TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 280)
                HStack {
                    Button(L("common.save")) { save() }.buttonStyle(.borderedProminent)
                    Button(L("plugins.reset")) { reset() }
                }
                if !message.isEmpty { Text(message).foregroundStyle(failed ? .red : .secondary) }
            }
        }.formStyle(.grouped).settingsPageSurface().onAppear { reload() }
    }
    private func reload() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(service.document ?? CompositionDocument(bundles: ["desktop"])) {
            text = String(decoding: data, as: UTF8.self)
        }
    }
    private func save() {
        guard isCurrent() else { return }
        do {
            try service.save(JSONDecoder().decode(CompositionDocument.self, from: Data(text.utf8)))
            message = service.restartRequired ? L("plugins.restart_required") : L("plugins.saved")
            failed = false
        } catch { message = error.localizedDescription; failed = true }
    }
    private func reset() {
        guard isCurrent() else { return }
        do {
            _ = try service.resetToShipped()
            reload(); message = L("plugins.reset_saved"); failed = false
        } catch { message = error.localizedDescription; failed = true }
    }
}
