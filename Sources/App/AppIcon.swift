import AppKit

enum AppIcon {

    @MainActor
    static func install() {
        let appearance = AppSettings.shared.appIconAppearance
        if appearance == .system {
            NSApp.applicationIconImage = nil
            return
        }

        guard let image = image(
            for: appearance,
            systemIsDark: systemIsDark,
            size: 512
        ) else {
            return
        }
        NSApp.applicationIconImage = image
    }

    static func image(for appearance: AppIconAppearance, systemIsDark: Bool, size: CGFloat? = nil) -> NSImage? {
        let resource = appearance.resourceName(systemIsDark: systemIsDark)
        return image(named: resource, size: size)
            ?? image(named: "AppIcon", size: size)
    }

    private static func image(named resource: String, size: CGFloat?) -> NSImage? {
        guard let url = AppResources.bundle.url(forResource: resource, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        if let size {
            image.size = NSSize(width: size, height: size)
        }
        return image
    }

    @MainActor
    private static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
