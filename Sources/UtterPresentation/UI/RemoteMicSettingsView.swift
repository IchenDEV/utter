import UtterPresentationContracts
import UtterContracts
import SwiftUI

/// The Xiaomi remote-microphone section of the Integrations tab.
struct RemoteMicSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var platform: PlatformProjection

    var body: some View {
        Section(L("settings.remote_mic")) {
            Toggle(isOn: $settings.remoteMicEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("settings.remote_mic"))
                    Text(L("settings.remote_mic_help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!platform.hasRemoteProvider)
            if settings.remoteMicEnabled {
                HStack {
                    Text(L("settings.remote_mic_status"))
                    Spacer()
                    Text(platform.remoteState.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(L("settings.remote_mic_gain"))
                    Slider(value: $settings.remoteMicGainDB, in: 0...24, step: 1)
                    Text("\(Int(settings.remoteMicGainDB)) dB")
                        .monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
    }
}
