import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
package enum RemoteMicPlugins {
    package static func capture() -> PluginRegistration {
        capture { XiaomiRemoteMicBridge(gainDB: $0) }
    }

    static func capture(makeBridge: @escaping (@escaping () -> Double) -> XiaomiRemoteMicBridge) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "remote-mic.xiaomi",
            requires: [DataServices.settings.required, IntegrationServices.diagnostics.required],
            provides: [RemoteMicServices.capture.reference, RemoteMicServices.control.reference]
        )) { context, _ in
            let settings = try context.require(DataServices.settings)
            let gain = RemoteMicGain(settings.values.remoteMicGainDB)
            let observation = settings.observe { gain.update($0.remoteMicGainDB) }
            try context.scope.onDispose { settings.removeObserver(observation) }
            let bridge = makeBridge { gain.value }
            let capture = RemoteMicCaptureManager(
                bridge: bridge, log: Log(service: try context.require(IntegrationServices.diagnostics))
            )
            let control = RemoteMicController(bridge: bridge, isReady: { context.isReady })
            control.setEnabled(settings.values.remoteMicEnabled)
            try context.scope.onRevoke {
                control.revoke()
                capture.revoke()
            }
            try context.scope.onDispose {
                await bridge.close()
                capture.close()
            }
            try context.scope.onReady { control.prepareIngress() }
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
