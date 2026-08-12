import AppKit
import Combine
import Foundation

@MainActor
extension AppDelegate {
    func observePhaseForIcon() {
        appState.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .recording:
                    self.startAnimatingIcon()
                default:
                    self.stopAnimatingIcon()
                }
            }
            .store(in: &cancellables)
    }

    func startAnimatingIcon() {
        iconTimer?.invalidate()
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.statusItem?.button?.image = Self.recordingIcon(level: self.appState.audioLevel)
            }
        }
    }

    func stopAnimatingIcon() {
        iconTimer?.invalidate()
        iconTimer = nil
        statusItem?.button?.image = Self.micIcon()
    }

    static func micIcon() -> NSImage {
        let name = AppSettings.shared.menuBarIcon.symbolName
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: ProductBrand.displayName) else {
            return NSImage()
        }
        img.isTemplate = true
        return img
    }

    func observeMenuBarIconSetting() {
        AppSettings.shared.$menuBarIcon
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.appState.isRecording else { return }
                self.statusItem?.button?.image = Self.micIcon()
            }
            .store(in: &cancellables)
    }

    func observeAppIconSetting() {
        AppSettings.shared.$appIconAppearance
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { _ in AppIcon.install() }
            .store(in: &cancellables)
    }

    func observeSystemAppearanceForIcon() {
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { _ in
                guard AppSettings.shared.appIconAppearance == .system else { return }
                AppIcon.install()
            }
            .store(in: &cancellables)
    }

    private static let recordingOrange = NSColor(red: 1.0, green: 0.624, blue: 0.04, alpha: 1.0)

    private static func recordingIcon(level: Float) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let barCount = 5
            let barWidth: CGFloat = 2.0
            let spacing: CGFloat = 1.5
            let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
            let startX = (rect.width - totalW) / 2
            let maxH: CGFloat = rect.height - 4
            let time = Date().timeIntervalSinceReferenceDate

            recordingOrange.setFill()
            for i in 0..<barCount {
                let offset = Double(i) / Double(barCount) * .pi * 2
                let wave = (sin(time * 10 + offset) + 1) / 2
                let normalized = CGFloat(max(level, 0.18))
                let barH = max(3, normalized * maxH * CGFloat(wave))
                let x = startX + CGFloat(i) * (barWidth + spacing)
                let y = (rect.height - barH) / 2
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: barH), xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}
