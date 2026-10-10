import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension AudioPlugins {
    package static func devices() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "audio.devices", provides: [AudioServices.devices.reference])) { context, _ in
            try context.provide(AudioServices.devices, value: NativeAudioDevices(isReady: { context.isReady }))
        }
    }
}

@MainActor
private final class NativeAudioDevices: AudioDeviceService {
    private let isReady: () -> Bool
    init(isReady: @escaping () -> Bool) { self.isReady = isReady }
    func availableMicrophones() -> [MicrophoneDescription] {
        isReady() ? AudioCaptureManager.availableMicrophones().map { MicrophoneDescription(id: $0.id, name: $0.name) } : []
    }
}
