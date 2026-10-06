#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import UtterContracts
import UtterRuntime

package enum PresentationRole: Equatable { case settings, menu, onboarding }

@MainActor
package struct PresentationContribution {
    package let id: String
    package let role: PresentationRole
    package let order: Int
    package let label: String
    package let symbol: String
    package let view: (PresentationContext) -> AnyView
    package init(id: String, role: PresentationRole, order: Int = 0, label: String = "", symbol: String = "",
                 view: @escaping (PresentationContext) -> AnyView) {
        self.id = id; self.role = role; self.order = order; self.label = label; self.symbol = symbol; self.view = view
    }
}

@MainActor
package struct PresentationContext {
    package let settings: AppSettings
    package let state: AppState
    package let openSettings: () -> Void
    package let applyReplacement: () -> Void
    package let copy: (String) -> Void
    package let completeOnboarding: () -> Void
    package let dismiss: () -> Void
    package let cancel: () -> Void
    package let stop: () -> Void
    package let recover: () -> Void
    package init(settings: AppSettings, state: AppState, openSettings: @escaping () -> Void,
                 applyReplacement: @escaping () -> Void, copy: @escaping (String) -> Void,
                 completeOnboarding: @escaping () -> Void, dismiss: @escaping () -> Void,
                 cancel: @escaping () -> Void, stop: @escaping () -> Void, recover: @escaping () -> Void) {
        self.settings = settings; self.state = state; self.openSettings = openSettings
        self.applyReplacement = applyReplacement; self.copy = copy; self.completeOnboarding = completeOnboarding
        self.dismiss = dismiss; self.cancel = cancel; self.stop = stop; self.recover = recover
    }
}

@MainActor
package protocol PresentationCatalog: AnyObject {
    func contributions(for role: PresentationRole) -> [PresentationContribution]
    func register(_ contribution: PresentationContribution, scope: PluginScope) throws
}

@MainActor
package protocol DesktopPresentationService: AnyObject {
    func openSettings()
}

#if canImport(AppKit)
@MainActor
package protocol OverlayPresentationService: AnyObject {
    func show(context: PresentationContext, targetApp: NSRunningApplication?)
    func hide()
}

@MainActor
package protocol IconPresentationService: AnyObject {
    func install(appearance: AppIconAppearance)
    func menuIcon(_ icon: MenuBarIcon, phase: AppPhase) -> NSImage?
}
#endif

package enum PresentationServices {
    package static let catalog = ServiceKey<any PresentationCatalog>("presentation.catalog")
    package static let desktop = ServiceKey<any DesktopPresentationService>("presentation.desktop")
    #if canImport(AppKit)
    package static let overlay = ServiceKey<any OverlayPresentationService>("presentation.overlay")
    package static let icons = ServiceKey<any IconPresentationService>("presentation.icons")
    #endif
}
