import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension MacPlugins {
    package static func hotkeys() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "mac.hotkeys", requires: [DataServices.settings.required, IntegrationServices.diagnostics.required],
            provides: [MacServices.hotkeys.reference]
        )) { context, _ in
            let service = HotkeyIngress(
                settings: try context.require(DataServices.settings),
                log: Log(service: try context.require(IntegrationServices.diagnostics)), isReady: { context.isReady }
            )
            try context.scope.onRevoke { service.revoke() }
            try context.scope.onDispose { await service.close() }
            try context.scope.onReady { service.prepareIngress() }
            try context.provide(MacServices.hotkeys, value: service)
        }
    }

    package static func sounds() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "mac.sounds", requires: [DataServices.settings.required], provides: [MacServices.sounds.reference]
        )) { context, _ in
            let settings = try context.require(DataServices.settings)
            let service = SoundPlayer(enabled: { context.isReady && settings.values.playSounds })
            try context.scope.onRevoke { service.close() }
            try context.provide(MacServices.sounds, value: service)
        }
    }

    package static func loginItem() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "mac.login-item", provides: [MacServices.loginItem.reference])) { context, _ in
            try context.provide(MacServices.loginItem, value: ScopedLoginItem(isCurrent: { context.isReady }))
        }
    }
}

@MainActor
private final class ScopedLoginItem: LoginItemService {
    private let isCurrent: () -> Bool
    init(isCurrent: @escaping () -> Bool) { self.isCurrent = isCurrent }
    var isEnabled: Bool { LaunchAtLoginService.isEnabled }
    var requiresApproval: Bool { LaunchAtLoginService.requiresApproval }
    func setEnabled(_ enabled: Bool) throws {
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        try LaunchAtLoginService.setEnabled(enabled)
    }
}
