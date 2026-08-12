import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IntegrationsSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var approvedClients: [IntegrationClient] = []
    private let registry = IntegrationClientRegistry()

    var body: some View {
        VStack(spacing: 0) {
            SettingsPageHeader(
                kind: .integrations,
                title: L("settings.page.integrations.title"),
                subtitle: L("settings.page.integrations.subtitle")
            )
            Divider()

            Form {
                Section(L("settings.developer_interface")) {
                    Toggle(isOn: $settings.developerInterfaceEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.developer_interface"))
                            Text(L("settings.developer_interface_help"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L("settings.developer_registered_apps")) {
                    if approvedClients.isEmpty {
                        Text(L("settings.developer_no_registered_apps"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(approvedClients) { client in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.displayName)
                                    Text(clientDetail(client))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button(L("common.delete")) {
                                    registry.revoke(clientID: client.id)
                                    refreshClients()
                                }
                            }
                        }
                    }

                    Button(L("settings.developer_add_app")) { addApp() }
                    Button(L("settings.developer_register_cli")) { registerCLIHelper() }
                }

                Section("HTTP") {
                    LabeledContent(L("settings.developer_http_address")) {
                        Text("127.0.0.1:\(settings.developerHTTPPort)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    LabeledContent(L("settings.developer_http_token")) {
                        Text(settings.developerHTTPToken)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Button(L("settings.developer_reset_token")) {
                        settings.resetDeveloperHTTPToken()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .settingsPageSurface()
        .onAppear(perform: refreshClients)
    }

    private func refreshClients() {
        approvedClients = registry.approvedClients().filter { $0.transport != .http }
    }

    private func registerCLIHelper() {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/opentype-cli")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        registry.approve(IntegrationClient.localCLI(executablePath: url.resolvingSymlinksInPath().path))
        refreshClients()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        registry.approve(IntegrationClient.appIdentity(url: url, transport: .xpc))
        refreshClients()
    }

    private func clientDetail(_ client: IntegrationClient) -> String {
        let identity = client.bundleIdentifier ?? client.codeRequirement ?? client.id
        return "\(client.transport.rawValue) · \(identity)"
    }
}
