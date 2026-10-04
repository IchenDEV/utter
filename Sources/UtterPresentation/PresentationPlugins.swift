import AppKit
import SwiftUI
import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
import UtterRuntime

@MainActor
package enum PresentationPlugins {
    package static func desktop() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "presentation.desktop", requires: [
            PresentationServices.catalog.required, DataServices.settings.required, DataServices.credentials.required,
            IntegrationServices.diagnostics.required, SessionServices.execution.optional, SessionServices.outputs.optional,
            PresentationServices.overlay.optional, PresentationServices.icons.optional
        ], provides: [PresentationServices.desktop.reference])) { context, _ in
            let host = NativeDesktopHost(catalog: try context.require(PresentationServices.catalog),
                settings: try context.require(DataServices.settings), credentials: try context.require(DataServices.credentials),
                execution: try context.optional(SessionServices.execution), outputs: try context.optional(SessionServices.outputs),
                overlay: try context.optional(PresentationServices.overlay), icons: try context.optional(PresentationServices.icons),
                diagnostics: try context.require(IntegrationServices.diagnostics), isCurrent: { context.isCurrent })
            try context.scope.onReady { host.start() }
            try context.scope.onRevoke { host.close() }
            try context.provide(PresentationServices.desktop, value: host)
        }
    }
    package static func catalog() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "presentation.catalog", provides: [PresentationServices.catalog.reference])) { context, _ in
            try context.provide(PresentationServices.catalog, value: PresentationRegistry())
        }
    }

    package static func menu() -> PluginRegistration {
        contribution(id: "presentation.menu", role: .menu) { context, _ in
            { presentation in
                AnyView(MenuBarView(onOpenSettings: presentation.openSettings,
                    onApplyPendingReplacement: presentation.applyReplacement, onCopy: presentation.copy,
                    onQuit: { NSApp.terminate(nil) }))
            }
        }
    }

    package static func overlay() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "presentation.overlay", requires: [MacServices.screen.optional],
            provides: [PresentationServices.overlay.reference])) { context, _ in
            let service = NativeOverlayPresentation(screen: try context.optional(MacServices.screen))
            try context.scope.onRevoke { service.hide() }
            try context.provide(PresentationServices.overlay, value: service)
        }
    }

    package static func icons() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "presentation.icons", provides: [PresentationServices.icons.reference])) { context, _ in
            try context.provide(PresentationServices.icons, value: NativeIconPresentation())
        }
    }

    static func contribution(id: String, role: PresentationRole, order: Int = 0, label: String = "", symbol: String = "",
        requires: [ServiceRequirement] = [],
        make: @escaping (PluginContext, [String: ConfigurationValue]) throws -> (PresentationContext) -> AnyView) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: id, requires: [PresentationServices.catalog.required] + requires)) { context, configuration in
            let view = try make(context, configuration)
            try context.require(PresentationServices.catalog).register(PresentationContribution(id: id, role: role,
                order: order, label: label, symbol: symbol, view: { presentation in
                    guard context.isCurrent else { return AnyView(EmptyView()) }
                    return view(presentation)
                }), scope: context.scope)
        }
    }

    static let platformRequirements: [ServiceRequirement] = [RemoteMicServices.control.optional, MacServices.loginItem.optional,
        AudioServices.devices.optional, MacServices.screen.optional, IntegrationServices.diagnostics.required]
    static func platform(_ context: PluginContext) throws -> PlatformProjection {
        let projection = PlatformProjection(remote: try context.optional(RemoteMicServices.control), login: try context.optional(MacServices.loginItem),
            devices: try context.optional(AudioServices.devices), screen: try context.optional(MacServices.screen),
            diagnostics: try context.require(IntegrationServices.diagnostics))
        try context.scope.onDispose { projection.dispose() }
        return projection
    }
}

@MainActor
private final class NativeOverlayPresentation: OverlayPresentationService {
    private let panel: OverlayPanel
    init(screen: (any ScreenCaptureService)?) { panel = OverlayPanel(screen: screen) }
    func show(context: PresentationContext, targetApp: NSRunningApplication?) {
        panel.show(appState: context.state, targetApp: targetApp, onCancel: context.cancel, onConfirm: context.stop,
            onCopy: { context.copy(context.state.snapshot.text) }, onRecover: context.recover, onDismiss: context.dismiss)
    }
    func hide() { panel.hide() }
}

@MainActor
private final class NativeIconPresentation: IconPresentationService {
    func install(appearance: AppIconAppearance) { AppIcon.install(appearance: appearance) }
    func menuIcon(_ icon: MenuBarIcon, phase: AppPhase) -> NSImage? {
        let image = NSImage(systemSymbolName: phase == .recording ? "waveform" : icon.symbolName,
                            accessibilityDescription: ProductBrand.displayName)
        image?.isTemplate = true
        return image
    }
}
