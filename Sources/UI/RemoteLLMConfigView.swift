import UtterContracts
import SwiftUI

struct RemoteLLMConfigView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var testMessage: String?
    @State private var testSuccess: Bool?
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker(L("remote.provider"), selection: $settings.remoteProvider) {
                    ForEach(RemoteProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                Text(settings.remoteProvider.apiFormat == .anthropic ? "Anthropic API" : "OpenAI API")
                    .font(.system(size: 9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
            .onChange(of: settings.remoteProvider) { _, newProvider in
                settings.remoteBaseURL = newProvider.defaultBaseURL
                settings.remoteModel = newProvider.defaultModel
            }

            SecureField(L("remote.api_key"), text: $settings.remoteAPIKey)
                .textFieldStyle(.roundedBorder)
            TextField(L("remote.base_url"), text: $settings.remoteBaseURL)
                .textFieldStyle(.roundedBorder)
            TextField(L("remote.model"), text: $settings.remoteModel)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button(L("remote.test")) {
                    Task { await testRemoteConnection() }
                }
                .controlSize(.small)
                .disabled(isTesting || settings.remoteAPIKey.isEmpty || settings.remoteBaseURL.isEmpty || settings.remoteModel.isEmpty)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
                if let testMessage {
                    Text(testMessage)
                        .font(.system(size: 10))
                        .foregroundStyle((testSuccess ?? false) ? .green : .red)
                }
            }
        }
        .padding(.leading, 4)
    }

    @MainActor
    private func testRemoteConnection() async {
        testMessage = nil
        testSuccess = nil
        isTesting = true
        defer { isTesting = false }

        let client = RemoteLLMClient()
        do {
            _ = try await client.generate(
                prompt: "Hi",
                systemPrompt: nil,
                baseURL: settings.remoteBaseURL,
                apiKey: settings.remoteAPIKey,
                model: settings.remoteModel,
                provider: settings.remoteProvider,
                maxTokens: 10
            )
            testMessage = L("remote.test_success")
            testSuccess = true
        } catch {
            testMessage = "\(L("remote.test_failed")): \(error.localizedDescription)"
            testSuccess = false
        }
    }
}
