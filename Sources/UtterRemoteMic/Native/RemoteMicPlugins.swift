import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
package enum RemoteMicPlugins {
    package static func capture() -> PluginRegistration {
        capture(
            makeBridge: { XiaomiRemoteMicBridge(gainDB: $0) },
            makeKeyRemap: { RemoteKeyMappingController(provider: RemoteHIDServiceProvider()) }
        )
    }

    static func capture(
        makeBridge: @escaping (@escaping () -> Double) -> XiaomiRemoteMicBridge,
        makeKeyRemap: @escaping @MainActor () -> RemoteKeyMappingController
    ) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "remote-mic.xiaomi",
            requires: [DataServices.settings.required, IntegrationServices.diagnostics.required],
            provides: [RemoteMicServices.capture.reference, RemoteMicServices.control.reference]
        )) { context, _ in
            let settings = try context.require(DataServices.settings)
            let gain = RemoteMicGain(settings.values.remoteMicGainDB)
            let keyRemap = makeKeyRemap()
            // The key remap follows its own setting and is independent of the remote-mic toggle.
            let observation = settings.observe {
                gain.update($0.remoteMicGainDB)
                if context.isReady { keyRemap.setEnabled($0.remoteKeyRemapEnabled) }
            }
            try context.scope.onDispose { settings.removeObserver(observation) }
            let bridge = makeBridge { gain.value }
            let capture = RemoteMicCaptureManager(
                bridge: bridge, log: Log(service: try context.require(IntegrationServices.diagnostics))
            )
            let control = RemoteMicController(bridge: bridge, isReady: { context.isReady })
            control.setEnabled(settings.values.remoteMicEnabled)
            keyRemap.onChange = { [weak control] state, count in control?.setKeyRemap(state, reapplyCount: count) }
            control.onBridgeReady = { keyRemap.expectRemote() }
            try context.scope.onRevoke {
                keyRemap.setEnabled(false)
                control.revoke()
                capture.revoke()
            }
            try context.scope.onDispose {
                keyRemap.setEnabled(false)
                await bridge.close()
                capture.close()
            }
            try context.scope.onReady {
                keyRemap.setEnabled(settings.values.remoteKeyRemapEnabled)
                control.prepareIngress()
            }
            try context.provide(RemoteMicServices.capture, value: capture)
            try context.provide(RemoteMicServices.control, value: control)
        }
    }
}

private final class RemoteMicGain: @unchecked Sendable {
    private let lock = NSLock()
    private var gain: Double
    init(_ gain: Double) { self.gain = gain }
    var value: Double {
        lock.lock()
        defer { lock.unlock() }
        return gain
    }
    func update(_ gain: Double) {
        lock.lock()
        defer { lock.unlock() }
        self.gain = gain
    }
}
